import type { AdminClient } from "./supabase.ts";
import { inspectImage } from "./images.ts";
import { ServiceError } from "./http.ts";

type ThumbnailMedia = {
  id: string;
  user_id: string;
  batch_id: string;
  thumbnail_path: string | null;
  deleted_at: string | null;
};
const mediaColumns = "id,user_id,batch_id,thumbnail_path,deleted_at";

function thumbnailPath(media: ThumbnailMedia): string {
  return `${media.user_id}/${media.batch_id}/${media.id}.thumb.jpg`;
}

/** A terminal tombstone authorizes only this immutable identity's derived pixels. */
async function discardTombstonedThumbnail(
  client: AdminClient,
  media: ThumbnailMedia,
): Promise<void> {
  if (!media.deleted_at) {
    throw new ServiceError(
      "THUMBNAIL_LINK_PENDING",
      "Deletion is not confirmed",
      503,
      true,
    );
  }
  const removed = await client.storage.from("evidence").remove([
    thumbnailPath(media),
  ]);
  if (removed.error) {
    throw new ServiceError(
      "THUMBNAIL_CLEANUP_PENDING",
      "Deleted thumbnail cleanup is pending",
      503,
      true,
    );
  }
}

/** Only derived pixels are used; never fetch or transform an archival original. */
export async function createThumbnail(
  client: AdminClient,
  mediaId: string,
): Promise<void> {
  const media = await client.from("media").select(mediaColumns).eq(
    "id",
    mediaId,
  ).maybeSingle();
  if (media.error) {
    throw new ServiceError(
      "THUMBNAIL_READ_PENDING",
      "Thumbnail row unavailable",
      503,
      true,
    );
  }
  if (!media.data) return;
  if (media.data.deleted_at) {
    await discardTombstonedThumbnail(client, media.data);
    return;
  }
  if (media.data.thumbnail_path) return;
  const analysis = await client.from("media_analysis").select(
    "data_url,expires_at",
  ).eq("media_id", mediaId).maybeSingle();
  if (analysis.error) {
    throw new ServiceError(
      "THUMBNAIL_READ_PENDING",
      "Derived pixels unavailable",
      503,
      true,
    );
  }
  if (
    !analysis.data?.data_url || new Date(analysis.data.expires_at) <= new Date()
  ) return;
  const base64 = String(analysis.data.data_url).split(",")[1];
  const pixels = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  const thumbnail = await inspectImage(pixels, "UTC", 480);
  const path = thumbnailPath(media.data);
  const bucket = client.storage.from("evidence");
  const saved = await bucket.upload(path, thumbnail.jpeg, {
    contentType: "image/jpeg",
    upsert: false,
  });
  if (saved.error) {
    const existing = await bucket.download(path);
    if (existing.error || !existing.data) {
      throw new ServiceError(
        "THUMBNAIL_SAVE_PENDING",
        "Thumbnail upload not confirmed",
        503,
        true,
      );
    }
    const bytes = new Uint8Array(await existing.data.arrayBuffer());
    if (
      bytes.length !== thumbnail.jpeg.length ||
      bytes.some((v, i) => v !== thumbnail.jpeg[i])
    ) {
      throw new ServiceError(
        "THUMBNAIL_CONFLICT",
        "Immutable thumbnail differs",
        409,
        false,
      );
    }
  }
  // A successful zero-row update is not a successful link: deletion may have
  // completed while Storage was uploading. Never infer deletion from an error.
  const linked = await client.from("media").update({ thumbnail_path: path })
    .eq("id", mediaId).eq("user_id", media.data.user_id)
    .eq("batch_id", media.data.batch_id).is("deleted_at", null)
    .select("id").maybeSingle();
  if (linked.error) {
    throw new ServiceError(
      "THUMBNAIL_LINK_PENDING",
      "Thumbnail link not confirmed",
      503,
      true,
    );
  }
  if (linked.data) return;
  const current = await client.from("media").select(mediaColumns)
    .eq("id", mediaId).eq("user_id", media.data.user_id)
    .eq("batch_id", media.data.batch_id).maybeSingle();
  if (current.error || !current.data || !current.data.deleted_at) {
    // Missing/unknown state has no deletion authority. Keep the private object
    // for reconciliation, rather than risking a committed credential image.
    throw new ServiceError(
      "THUMBNAIL_LINK_PENDING",
      "Thumbnail ownership is awaiting reconciliation",
      503,
      true,
    );
  }
  await discardTombstonedThumbnail(client, current.data);
}
