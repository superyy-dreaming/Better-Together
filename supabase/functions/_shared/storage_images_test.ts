import jpeg from "npm:jpeg-js@0.4.4";
import {
  type ImageBucket,
  uploadAvatar,
} from "./storage_images.ts";
import { ServiceError } from "./http.ts";

function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
const bytes = new Uint8Array(
  jpeg.encode({
    width: 512,
    height: 512,
    data: new Uint8Array(512 * 512 * 4).fill(200),
  }, 85).data,
);
function storageMock(failTransform = false, failFinal = false) {
  const uploads: { path: string; contentType: string }[] = [];
  const removed: string[][] = [];
  const downloads: {
    path: string;
    width: number;
    format: string;
    resize: string;
  }[] = [];
  const bucket: ImageBucket = {
    upload: (path, _bytes, options) => {
      uploads.push({ path, contentType: options.contentType });
      return Promise.resolve({
        error: failFinal
          ? { name: "StorageError" }
          : null,
      });
    },
    remove: (paths) => {
      removed.push(paths);
      return Promise.resolve({ error: null });
    },
  };
  return { bucket, uploads, removed, downloads };
}
Deno.test("avatar is private owner-scoped normalized JPEG without checkin date or hash reservation", async () => {
  const previous = Deno.env.get("MEDIA_IMAGE_MODE");
  Deno.env.set("MEDIA_IMAGE_MODE", "storage");
  try {
    const mock = storageMock();
    const result = await uploadAvatar(
      mock.bucket,
      "owner-id",
      new File([bytes], "old-avatar.jpg"),
      new Date("2026-11-18T00:00:00Z"),
    );
    assert(
      result.source === "avatar" && result.path.startsWith("owner-id/") &&
        result.path.endsWith(".jpg"),
      "Avatar path is not owner scoped",
    );
    assert(mock.uploads.length === 1 && mock.uploads[0].contentType === "image/jpeg", "Single normalized avatar upload required");
    assert(mock.downloads.length === 0, "Avatar must not depend on Storage Image Transform");
    assert(mock.removed.length === 0, "No compensating deletes");
  } finally {
    previous === undefined
      ? Deno.env.delete("MEDIA_IMAGE_MODE")
      : Deno.env.set("MEDIA_IMAGE_MODE", previous);
  }
});
Deno.test("avatar enforces size and supported format before storing bytes", async () => {
  for (
    const file of [
      new File([new Uint8Array(5 * 1024 * 1024 + 1)], "big.jpg"),
      new File([new Uint8Array([0, 0, 1])], "bad.jpg"),
    ]
  ) {
    const mock = storageMock();
    try {
      await uploadAvatar(mock.bucket, "owner", file);
      throw new Error("Accepted invalid avatar");
    } catch (error) {
      assert(error instanceof ServiceError, "Expected validation error");
    }
    assert(mock.uploads.length === 0, "Stored invalid avatar");
  }
});
Deno.test("avatar preserves objects when upload result is unknown", async () => {
  const mock = storageMock(false,true);
  try { await uploadAvatar(mock.bucket,"owner",new File([bytes],"avatar.jpg")); throw new Error("Accepted failed upload"); }
  catch(error) { assert(error instanceof ServiceError && error.retryable,"Observable retryable failure required"); }
  assert(mock.removed.length===0,"Must never delete on an unknown commit result");
});
Deno.test("avatar works even when transform is unavailable", async () => {
  const mock = storageMock(true);
  await uploadAvatar(mock.bucket,"owner",new File([bytes],"avatar.jpg"));
  assert(mock.downloads.length===0 && mock.uploads.length===1,"Transform was used");
});
