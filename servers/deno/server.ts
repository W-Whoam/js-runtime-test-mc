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
