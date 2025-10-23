#!/bin/bash

# Minecraft Protocol Performance Monorepo Setup
# Creates a monorepo for testing Deno and Bun TCP performance with proper varint handling

# Create directory structure
mkdir -p servers/{deno,bun}
mkdir -p clients/{deno,bun}

# ===== DENO SERVER =====
cat > servers/deno/server.ts << 'EOF'
import { decodeVarint32, encodeVarint } from "@std/encoding/varint";

const TCP_PORT = 25565;
const HOST = "127.0.0.1";
const DEBUG = Deno.env.get("DEBUG") === "1";

const listener = Deno.listen({ hostname: HOST, port: TCP_PORT });
console.log(`[Deno Server] Listening on ${HOST}:${TCP_PORT}`);
if (DEBUG) console.log("[Deno Server] Debug mode enabled");

let connectionCount = 0;

for await (const conn of listener) {
  const connId = ++connectionCount;
  if (DEBUG) console.log(`[Deno Server] Connection #${connId} established`);
  
  (async () => {
    const buf = new Uint8Array(2048);
    let packetCount = 0;
    
    try {
      while (true) {
        const n = await conn.read(buf);
        if (n === null) break;
        
        // Decode varint to process packet
        try {
          const [length, varintBytes] = decodeVarint32(buf.slice(0, n));
          packetCount++;
          
          if (DEBUG && packetCount % 1000 === 0) {
            console.log(`[Deno Server] Conn #${connId}: Processed ${packetCount} packets`);
          }
        } catch (_e) {
          if (DEBUG) console.log(`[Deno Server] Conn #${connId}: Invalid varint`);
        }
        
        // Echo back
        await conn.write(buf.subarray(0, n));
      }
    } catch (e) {
      if (DEBUG) console.log(`[Deno Server] Conn #${connId}: Error - ${e}`);
    }
    
    if (DEBUG) console.log(`[Deno Server] Conn #${connId}: Closed after ${packetCount} packets`);
    conn.close();
  })();
}
EOF

# ===== DENO CLIENT =====
cat > clients/deno/client.ts << 'EOF'
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
EOF

# ===== BUN SERVER =====
cat > servers/bun/server.ts << 'EOF'
import { decodeVarint32, encodeVarint } from "@std/encoding/varint";

const TCP_PORT = 25565;
const HOST = "127.0.0.1";
const DEBUG = process.env.DEBUG === "1";

console.log(`[Bun Server] Listening on ${HOST}:${TCP_PORT}`);
if (DEBUG) console.log("[Bun Server] Debug mode enabled");

let connectionCount = 0;

const server = Bun.listen({
  hostname: HOST,
  port: TCP_PORT,
  socket: {
    open(socket) {
      const connId = ++connectionCount;
      socket.data = { connId, packetCount: 0 };
      if (DEBUG) console.log(`[Bun Server] Connection #${connId} established`);
    },
    
    data(socket, data) {
      try {
        const [length, varintBytes] = decodeVarint32(data);
        socket.data.packetCount++;
        
        if (DEBUG && socket.data.packetCount % 1000 === 0) {
          console.log(`[Bun Server] Conn #${socket.data.connId}: Processed ${socket.data.packetCount} packets`);
        }
      } catch (_e) {
        if (DEBUG) console.log(`[Bun Server] Conn #${socket.data.connId}: Invalid varint`);
      }
      
      socket.write(data);
    },
    
    close(socket) {
      if (DEBUG) console.log(`[Bun Server] Conn #${socket.data.connId}: Closed after ${socket.data.packetCount} packets`);
    },
    
    error(socket, error) {
      console.error(`[Bun Server] Socket error:`, error.message);
    }
  },
});
EOF

# ===== BUN CLIENT =====
cat > clients/bun/client.ts << 'EOF'
import { decodeVarint32, encodeVarint } from "@std/encoding/varint";

const TCP_PORT = 25565;
const HOST = "127.0.0.1";
const PACKETS_PER_WORKER = 5000;
const PACKET_SIZES = [8, 16, 32, 64, 128, 256, 512, 1024];
const NUM_WORKERS = parseInt(process.env.WORKERS || "1");
const DEBUG = process.env.DEBUG === "1";

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

  return new Promise<any>((resolve) => {
    let currentPacket = 0;
    let socket: any = null;
    let reqStart = 0;

    const connectAndRun = () => {
      socket = Bun.connect({
        hostname: HOST,
        port: TCP_PORT,
        socket: {
          open(sock) {
            if (DEBUG) console.log(`[Bun Client] Worker ${workerId}: Connected for ${packetSize}B test`);
            sendNext();
          },

          data(sock, data) {
            try {
              decodeVarint32(data);
            } catch (e) {
              if (DEBUG) console.log(`[Bun Client] Worker ${workerId}: Failed to decode response`);
            }
            
            const latency = performance.now() - reqStart;
            results.push(latency);
            
            if (DEBUG && currentPacket > 0 && currentPacket % 1000 === 0) {
              console.log(`[Bun Client] Worker ${workerId}: ${currentPacket}/${PACKETS_PER_WORKER} packets sent`);
            }
            
            currentPacket++;
            sendNext();
          },

          error(sock, error) {
            console.error(`[Bun Client] Worker ${workerId}: Socket error -`, error.message);
            finish();
          },

          close(sock) {
            if (DEBUG) console.log(`[Bun Client] Worker ${workerId}: Connection closed`);
            finish();
          }
        }
      });
    };

    const sendNext = () => {
      if (currentPacket >= PACKETS_PER_WORKER) {
        finish();
        return;
      }

      Promise.resolve(socket).then((sock) => {
        const packet = generateMinecraftPacket(packetSize);
        reqStart = performance.now();
        sock.write(packet);
      }).catch((e) => {
        if (DEBUG) console.log(`[Bun Client] Worker ${workerId}: Write error -`, e);
        finish();
      });
    };

    const finish = () => {
      const totalTime = performance.now() - startTime;
      const validResults = results.filter(r => r > 0);

      Promise.resolve(socket).then(s => s.end?.()).catch(() => {});

      resolve({
        runtime: "bun",
        protocol: "tcp",
        packetSize,
        packetsPerSecond: (validResults.length / totalTime) * 1000,
        totalTime,
        minLatency: validResults.length > 0 ? Math.min(...validResults) : 0,
        maxLatency: validResults.length > 0 ? Math.max(...validResults) : 0,
        avgLatency: validResults.length > 0 ? validResults.reduce((a, b) => a + b, 0) / validResults.length : 0,
      });
    };

    connectAndRun();
  });
}

async function runWorker(workerId: number) {
  const results = [];
  for (const size of PACKET_SIZES) {
    try {
      if (DEBUG) console.log(`[Bun Client] Worker ${workerId}: Starting ${size}B test...`);
      const result = await benchmarkTCP(size, workerId);
      if (result) results.push(result);
    } catch (e) {
      console.error(`[Bun Client] Worker ${workerId} error testing ${size}B:`, (e as Error).message);
    }
  }
  return results;
}

async function run() {
  console.log(`\n[Bun Client] Starting TCP benchmarks with ${NUM_WORKERS} worker(s)...`);
  if (DEBUG) console.log("[Bun Client] Debug mode enabled\n");
  await new Promise(r => setTimeout(r, 500));

  if (NUM_WORKERS === 1) {
    for (const size of PACKET_SIZES) {
      try {
        console.log(`[Bun Client] Testing ${size}B packets...`);
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
  
  console.log(`\n✓ Bun benchmarks complete (${NUM_WORKERS} worker(s))!\n`);
}

run().catch(console.error);
EOF

# ===== README =====
cat > README.md << 'EOF'
# Minecraft Protocol Performance Test

High-performance monorepo for benchmarking Deno vs Bun TCP performance with Minecraft Protocol varint encoding/decoding.

## 🏗️ Structure

```
minecraft-perf-test/
├── servers/
│   ├── deno/server.ts      # Deno TCP echo server
│   └── bun/server.ts       # Bun TCP echo server
├── clients/
│   ├── deno/client.ts      # Deno benchmark client
│   └── bun/client.ts       # Bun benchmark client
└── README.md
```

## 🚀 Quick Start

### Prerequisites
- **Deno**: Install from https://deno.land/
- **Bun**: Install from https://bun.sh/

### Running Tests

#### Basic Test (4 terminals)

**Terminal 1: Deno Server**
```bash
deno run --allow-net --allow-env servers/deno/server.ts
```

**Terminal 2: Deno Client**
```bash
deno run --allow-net --allow-env clients/deno/client.ts
```

**Terminal 3: Bun Server**
```bash
bun servers/bun/server.ts
```

**Terminal 4: Bun Client**
```bash
bun clients/bun/client.ts
```

#### Debug Mode (See Progress)

```bash
# Server with debug logging
DEBUG=1 deno run --allow-net --allow-env servers/deno/server.ts

# Client with debug logging (shows progress every 1000 packets)
DEBUG=1 deno run --allow-net --allow-env clients/deno/client.ts

# Same for Bun
DEBUG=1 bun servers/bun/server.ts
DEBUG=1 bun clients/bun/client.ts
```

#### Multi-Worker Test

```bash
# Deno with 4 concurrent workers
WORKERS=4 deno run --allow-net --allow-env clients/deno/client.ts

# Bun with 4 concurrent workers
WORKERS=4 bun clients/bun/client.ts

# With debug output
DEBUG=1 WORKERS=4 deno run --allow-net --allow-env clients/deno/client.ts
```

## 🔧 Features

### Realistic Minecraft Protocol Simulation
- **Varint Length Prefixes**: Every packet starts with a varint-encoded length
- **Varint Decoding**: Servers decode the length to validate packet structure
- **Echo Pattern**: Servers echo back the full packet for latency measurement

### Performance Metrics
- **Packets Per Second (pps)**: Total throughput
- **Average Latency**: Mean round-trip time in milliseconds
- **Min/Max Latency**: Best and worst case response times
- **Multiple Packet Sizes**: Tests 8B to 1KB packets

### Debug Features
- **Progress Indicators**: See "Testing XB packets..." for each size
- **Debug Mode**: Set `DEBUG=1` to see detailed packet counts every 1000 packets
- **Connection Tracking**: See when connections open/close and how many packets processed

## 📊 Example Output

```
[Deno Client] Starting TCP benchmarks with 1 worker(s)...

[Deno Client] Testing 8B packets...
TCP    8B:    45231 pps | avg   0.22ms | min 0.15ms | max 2.34ms
[Deno Client] Testing 16B packets...
TCP   16B:    43892 pps | avg   0.23ms | min 0.16ms | max 2.11ms
[Deno Client] Testing 32B packets...
TCP   32B:    41203 pps | avg   0.24ms | min 0.17ms | max 2.45ms
...
✓ Deno benchmarks complete (1 worker(s))!
```

## 🎯 Troubleshooting

If tests hang:
1. Enable debug mode: `DEBUG=1`
2. Check if server is running
3. Verify correct port (25565)
4. Check for firewall issues

## 🔍 Technical Details

### Message Format
```
[Varint Length Prefix] [Random Payload Data]
```

### Varint Encoding
- Uses Protocol Buffer varint encoding (Minecraft standard)
- 1-5 bytes for 32-bit integers
- Most significant bit indicates continuation byte

### Why This Matters
- Real Minecraft packets use varint length prefixes
- Tests realistic encoding/decoding overhead
- Measures both throughput and latency under protocol constraints
EOF

echo "✅ Minecraft Protocol Performance Test setup complete!"
echo ""
echo "📁 Structure created:"
echo "   ├── servers/{deno,bun}/server.ts"
echo "   ├── clients/{deno,bun}/client.ts"
echo "   └── README.md"
echo ""
echo "🚀 Quick start (4 terminals):"
echo "   1. deno run --allow-net --allow-env servers/deno/server.ts"
echo "   2. deno run --allow-net --allow-env clients/deno/client.ts"
echo "   3. bun servers/bun/server.ts"
echo "   4. bun clients/bun/client.ts"
echo ""
echo "🔍 Debug mode (see progress):"
echo "   DEBUG=1 deno run --allow-net --allow-env clients/deno/client.ts"
echo "   DEBUG=1 bun clients/bun/client.ts"
echo ""
echo "⚡ Multi-worker test:"
echo "   WORKERS=4 deno run --allow-net --allow-env clients/deno/client.ts"