import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/app_repository.dart';

/// Never render provider exception text: it may contain tokens or request data.
/// A cancelled system authorization is a normal return to the login screen.
String? authFailureMessage(Object error) {
  if (error is SignInWithAppleAuthorizationException) {
    return error.code == AuthorizationErrorCode.canceled
        ? null
        : 'Apple 授权未完成，请重新点击「通过 Apple 继续」。';
  }
  if (error is SignInWithAppleNotSupportedException) {
    return '此设备暂不支持 Apple 登录，请使用邮箱验证码。';
  }
  if (error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException ||
      error is AuthRetryableFetchException) {
    return '暂时无法连接登录服务，请检查网络后重试。';
  }
  if (error is AuthException) {
    switch (error.code) {
      case 'provider_disabled':
      case 'oauth_provider_not_supported':
        return 'Apple 登录服务尚未就绪，请稍后重试或联系内测负责人。';
      case 'bad_jwt':
      case 'invalid_jwt':
      case 'bad_oauth_callback':
      case 'bad_oauth_state':
        return '登录凭证未通过验证，请重新授权后再试。';
      case 'otp_expired':
      case 'otp_disabled':
        return '验证码无效或已过期，请重新获取邮件中的验证码。';
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return '请求太频繁，请稍等片刻再试，并检查是否已收到邮件。';
      case 'email_address_not_authorized':
        return '邮件服务尚未开通此邮箱的发送权限，请使用 Apple 登录或联系内测负责人。';
      case 'email_address_invalid':
        return '请检查邮箱地址是否正确。';
      case 'signup_disabled':
        return '当前暂未开放新账号注册，请联系内测负责人。';
      case 'email_provider_disabled':
        return '邮箱登录服务尚未就绪，请使用 Apple 登录或稍后重试。';
    }
    if (error.statusCode == '429') {
      return '请求太频繁，请稍等片刻再试。';
    }
    if ((int.tryParse(error.statusCode ?? '') ?? 0) >= 500) {
      return '登录服务暂时不可用，请稍后重试。';
    }
  }
  if (error is AppException) {
    // Only locally authored validation messages are allowed through.
    switch (error.code) {
      case 'email_invalid':
        return '请填写有效的邮箱地址。';
      case 'otp_missing':
        return '请填写邮件中的验证码。';
      case 'apple_token_missing':
        return 'Apple 登录未返回身份信息，请重新授权。';
    }
  }
  return '登录未完成，请重试；若仍无法登录，请联系内测负责人。';
}
