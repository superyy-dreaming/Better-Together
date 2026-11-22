import 'dart:async';
import 'dart:typed_data';
import 'package:better_together/data/ai/ai_task_queue.dart';
import 'package:better_together/data/ai/ai_transport.dart';
import 'package:better_together/data/ai/device_ai_service.dart';
import 'package:better_together/domain/models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:timezone/data/latest.dart' as tzdata;
import 'device_ai_test.dart' show configured, photoId, memo, response;

class MemoryTasks implements AiTaskStorage {
 final rows=<String,List<AiPendingTask>>{};
 final complete=Completer<void>();
 @override Future<List<AiPendingTask>> read(String owner) async =>
  (rows[owner]??[]).map((t)=>AiPendingTask.fromJson(t.toJson())).toList();
 @override Future<void> write(String owner,List<AiPendingTask> tasks) async {
  rows[owner]=tasks;
  if(tasks.any((t)=>['complete','changed','needs_configuration','expired'].contains(t.state)) && !complete.isCompleted) complete.complete();
 }
}
JsonMap taskContext()=>{'timezone':'UTC','local_date':DateTime.now().toUtc().toIso8601String().substring(0,10),
 'created_at':DateTime.now().toUtc().toIso8601String(),'record_version':4,'photo_revision':2,'scope_team_id':null,
 'batch_id':'batch','source':'camera','result':{'status':'pending'},
 'plans':[{'id':'20000000-0000-4000-8000-000000000001','category':'study','title':'学习'}]};
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();tzdata.initializeTimeZones();
 test('persisted task resumes without a page and sends the original expected version',() async {
  final storage=MemoryTasks();storage.rows['owner']=[AiPendingTask(mediaId:photoId,owner:'owner',createdAt:DateTime.now().toUtc().toIso8601String())];
  final saves=<JsonMap>[];
  Future<Object?> api(String name,{JsonMap args=const {}})async {
   if(name=='save_byok_photo') {saves.add(args);return {'applied':true};}return taskContext();
  }
  final ai=DeviceAiService(currentOwner:()=> 'owner',api:api,store:await configured(),transport:AiTransport(clientFactory:()=>MockClient((r)async=>response(memo()))));
  final queue=AiTaskQueue(ai:ai,api:api,currentOwner:()=> 'owner',storage:storage,
   download:(id)async=>Uint8List.fromList(img.encodeJpg(img.Image(width:32,height:32))));
  await queue.start();await storage.complete.future.timeout(const Duration(seconds:5));
  expect(saves.single['expected_version'],4);expect(saves.single['expected_photo_revision'],2);
  expect(saves.single['idempotency_key'],isNotEmpty);
  expect(storage.rows.toString(),isNot(contains('synthetic-key')));
  expect(storage.rows['owner']!.single.state,'complete');
  await queue.dispose();await ai.dispose();
 });
 test('persisted stale version stops before download or provider request',() async {
  final storage=MemoryTasks();storage.rows['owner']=[AiPendingTask(mediaId:photoId,owner:'owner',createdAt:DateTime.now().toUtc().toIso8601String(),bound:true,expectedVersion:1,photoRevision:2)];
  final ai=DeviceAiService(currentOwner:()=> 'owner',api:(name,{args=const {}})async=>taskContext(),store:await configured());
  final queue=AiTaskQueue(ai:ai,api:(name,{args=const {}})async=>taskContext(),currentOwner:()=> 'owner',storage:storage,download:(id)async=>throw StateError('No download for stale tasks'));
  await queue.start();await storage.complete.future.timeout(const Duration(seconds:3));
  expect(storage.rows['owner']!.single.state,'changed');await queue.dispose();await ai.dispose();
 });
 test('account change or app suspension prevents a late result from being saved',()async {
  for(final suspend in [false,true]) {
   var owner='owner',saves=0;final began=Completer<void>(),release=Completer<void>();
   final storage=MemoryTasks();
   Future<Object?> api(String name,{JsonMap args=const {}})async {if(name=='save_byok_photo')saves++;return taskContext();}
   final ai=DeviceAiService(currentOwner:()=>owner,api:api,store:await configured(),transport:AiTransport(clientFactory:()=>MockClient((r)async {began.complete();await release.future;return response(memo());})));
   final queue=AiTaskQueue(ai:ai,api:api,currentOwner:()=>owner,storage:storage,download:(id)async=>Uint8List.fromList(img.encodeJpg(img.Image(width:32,height:32))));
   await queue.start();await queue.enqueue(photoId);await began.future.timeout(const Duration(seconds:5));
   if(suspend) {queue.didChangeAppLifecycleState(AppLifecycleState.paused);}else{owner='other';ai.invalidate();}
   release.complete();await Future<void>.delayed(const Duration(milliseconds:50));
   expect(saves,0);expect(storage.rows['owner'],isNotEmpty);
   await queue.dispose();await ai.dispose();
  }
 });
}
