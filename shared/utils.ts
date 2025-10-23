export function generateRandomPacket(size: number): Uint8Array {
  const packet = new Uint8Array(size);
  for (let i = 0; i < size; i++) {
    packet[i] = Math.floor(Math.random() * 256);
  }
  return packet;
}

export function createHandshakePacket(): Uint8Array {
  // Simplified Minecraft handshake packet
  const packet = new Uint8Array(10);
  packet[0] = 0x00; // Packet ID (Handshake)
  packet[1] = 0xF3; // Protocol version (latest)
  packet[2] = 0x09;
  return packet;
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 Bytes";
  const k = 1024;
  const sizes = ["Bytes", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + " " + sizes[i];
}
