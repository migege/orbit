-- Per-agent runner fan-out: a device enrollment can mint one Runner per agent.
ALTER TABLE "DeviceEnrollment" ADD COLUMN "agents" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
ALTER TABLE "DeviceEnrollment" ADD COLUMN "runners" JSONB;
