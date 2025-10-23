export const TCP_PORT = 25565;
export const UDP_PORT = 25566;
export const HOST = "127.0.0.1";

export const PACKET_SIZES = [8, 16, 32, 64, 128, 256, 512, 1024];
export const PACKETS_PER_SIZE = 10000;
export const CONCURRENT_CONNECTIONS = 10;

export interface BenchmarkResult {
  runtime: "deno" | "bun";
  protocol: "tcp" | "udp";
  packetSize: number;
  packetsPerSecond: number;
  totalTime: number;
  minLatency: number;
  maxLatency: number;
  avgLatency: number;
  memoryUsed: number;
}
