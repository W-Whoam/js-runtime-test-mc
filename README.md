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
