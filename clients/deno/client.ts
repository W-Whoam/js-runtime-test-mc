import { decodeVarint32, encodeVarint } from "@std/encoding/varint";

const TCP_PORT = 25565;
const HOST = "127.0.0.1";
const PACKETS_PER_WORKER = 5000;
const PACKET_SIZES = [8, 16, 32, 64, 128, 256, 512, 1024];
const NUM_WORKERS = parseInt(Deno.env.get("WORKERS") || "1");
const DEBUG = Deno.env.get("DEBUG") === "1";

function generateMinecraftPacket(size: number): Uint8Array {
  const lengthBytes = encodeVarint(size);
  const packet = new Uint8Array(lengthBytes.length + size);
  packet.set(lengthBytes, 0);
  for (let i = lengthBytes.length; i < packet.length; i++) {
    packet[i] = Math.floor(Math.random() * 256);
  }
  return packet;
}

async function benchmarkTCP(packetSize: number, workerId = 0) {
  const results: number[] = [];
  const startTime = performance.now();
  let conn: Deno.Conn | null = null;

  try {
    conn = await Deno.connect({ hostname: HOST, port: TCP_PORT });
    if (DEBUG) console.log(`[Deno Client] Worker ${workerId}: Connected for ${packetSize}B test`);
    
    for (let i = 0; i < PACKETS_PER_WORKER; i++) {
      const packet = generateMinecraftPacket(packetSize);
      const reqStart = performance.now();
      
      await conn.write(packet);
      
      const response = new Uint8Array(packet.length);
      const n = await conn.read(response);
      
      if (n === null) {
        if (DEBUG) console.log(`[Deno Client] Worker ${workerId}: Connection closed, reconnecting...`);
        conn.close();
        conn = await Deno.connect({ hostname: HOST, port: TCP_PORT });
        continue;
      }
      
      try {
        decodeVarint32(response);
      } catch (e) {
        if (DEBUG) console.log(`[Deno Client] Worker ${workerId}: Failed to decode response`);
      }
      
      const latency = performance.now() - reqStart;
      results.push(latency);
      
      if (DEBUG && i > 0 && i % 1000 === 0) {
        console.log(`[Deno Client] Worker ${workerId}: ${i}/${PACKETS_PER_WORKER} packets sent`);
      }
    }
  } finally {
    if (conn) conn.close();
  }

  const totalTime = performance.now() - startTime;
  const validResults = results.filter(r => r > 0);

  return {
    runtime: "deno",
    protocol: "tcp",
    packetSize,
    packetsPerSecond: (validResults.length / totalTime) * 1000,
    totalTime,
    minLatency: Math.min(...validResults),
    maxLatency: Math.max(...validResults),
    avgLatency: validResults.reduce((a, b) => a + b, 0) / validResults.length,
  };
}

async function runWorker(workerId: number) {
  const results = [];
  for (const size of PACKET_SIZES) {
    try {
      if (DEBUG) console.log(`[Deno Client] Worker ${workerId}: Starting ${size}B test...`);
      const result = await benchmarkTCP(size, workerId);
      if (result) results.push(result);
    } catch (e) {
      console.error(`[Deno Client] Worker ${workerId} error testing ${size}B:`, (e as Error).message);
    }
  }
  return results;
}

async function run() {
  console.log(`\n[Deno Client] Starting TCP benchmarks with ${NUM_WORKERS} worker(s)...`);
  if (DEBUG) console.log("[Deno Client] Debug mode enabled\n");
  await new Promise(r => setTimeout(r, 500));

  if (NUM_WORKERS === 1) {
    for (const size of PACKET_SIZES) {
      try {
        console.log(`[Deno Client] Testing ${size}B packets...`);
        const result = await benchmarkTCP(size);
        console.log(
          `TCP ${size.toString().padStart(4)}B: ${result.packetsPerSecond.toFixed(0).padStart(8)} pps | ` +
          `avg ${result.avgLatency.toFixed(2).padStart(6)}ms | ` +
          `min ${result.minLatency.toFixed(2)}ms | max ${result.maxLatency.toFixed(2)}ms`
        );
      } catch (e) {
        console.error(`Error testing ${size}B:`, (e as Error).message);
      }
    }
  } else {
    const workers = Array.from({ length: NUM_WORKERS }, (_, i) => runWorker(i));
    const allResults = await Promise.all(workers);
    
    for (let sizeIdx = 0; sizeIdx < PACKET_SIZES.length; sizeIdx++) {
      const size = PACKET_SIZES[sizeIdx];
      let totalPps = 0;
      let totalLatency = 0;
      let minLatency = Infinity;
      let maxLatency = 0;
      let validCount = 0;
      
      for (const workerResults of allResults) {
        if (workerResults[sizeIdx]) {
          const result = workerResults[sizeIdx];
          totalPps += result.packetsPerSecond;
          totalLatency += result.avgLatency;
          minLatency = Math.min(minLatency, result.minLatency);
          maxLatency = Math.max(maxLatency, result.maxLatency);
          validCount++;
        }
      }
      
      if (validCount > 0) {
        const avgLatency = totalLatency / validCount;
        console.log(
          `TCP ${size.toString().padStart(4)}B: ${totalPps.toFixed(0).padStart(8)} pps | ` +
          `avg ${avgLatency.toFixed(2).padStart(6)}ms | ` +
          `min ${minLatency.toFixed(2)}ms | max ${maxLatency.toFixed(2)}ms`
        );
      }
    }
  }
  
  console.log(`\n✓ Deno benchmarks complete (${NUM_WORKERS} worker(s))!\n`);
}

run().catch(console.error);
