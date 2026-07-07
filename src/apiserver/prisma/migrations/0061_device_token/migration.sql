-- DeviceToken: an iOS device's APNs token, owner-scoped, so the server can push "needs your reply"
-- alerts to a user's devices. `token` is the hex APNs device token (unique — one row per device);
-- `environment` picks the APNs host (production for App Store/TestFlight, sandbox for dev builds).
-- Rows cascade-delete with the user. Registered via POST /api/push/register (upsert by token).
CREATE TABLE "device_token" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "token" TEXT NOT NULL,
    "platform" TEXT NOT NULL DEFAULT 'ios',
    "environment" TEXT NOT NULL DEFAULT 'production',
    "bundle_id" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "device_token_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "device_token_token_key" ON "device_token"("token");

CREATE INDEX "device_token_user_id_idx" ON "device_token"("user_id");

ALTER TABLE "device_token" ADD CONSTRAINT "device_token_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE ON UPDATE CASCADE;
