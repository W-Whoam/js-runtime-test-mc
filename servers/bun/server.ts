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
