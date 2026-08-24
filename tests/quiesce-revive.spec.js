import net from "node:net";

let completeLookup;

test("leaks a socket stuck in dns lookup", () => {
  const socket = net.connect({
    host: "quiesce-revive.test",
    port: 1,
    lookup(_host, _options, callback) {
      completeLookup = callback;
    },
  });
  socket.on("error", () => { });
});

test("finishing the leaked lookup after cleanup shouldn't crash", () => {
  completeLookup(null, "127.0.0.1", 4);
});

