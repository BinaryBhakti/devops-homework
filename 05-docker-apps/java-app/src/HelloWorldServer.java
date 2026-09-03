import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.Executors;

/**
 * Minimal Hello World web server using the JDK's built-in HTTP server.
 * No external framework or build tool required.
 */
public class HelloWorldServer {

    private static final int PORT =
            Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));

    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", PORT), 0);

        server.createContext("/", exchange -> {
            String host;
            try {
                host = InetAddress.getLocalHost().getHostName();
            } catch (Exception e) {
                host = "unknown";
            }

            String body = """
                    <!doctype html>
                    <html>
                    <head><meta charset="utf-8"><title>Java Hello World</title>
                    <style>
                      body{font-family:system-ui,-apple-system,sans-serif;display:grid;
                           place-items:center;min-height:100vh;margin:0;
                           background:#1b1b1f;color:#f5f5f5}
                      .card{background:#26262b;padding:3rem 4rem;border-radius:14px;
                            text-align:center;border:1px solid #3a3a42}
                      h1{margin:0 0 .5rem;font-size:2.5rem;color:#f89820}
                      p{margin:.25rem 0;color:#a5a5b0}
                      code{background:#15151a;padding:.15rem .45rem;border-radius:5px;
                           color:#5382a1}
                    </style></head>
                    <body><div class="card">
                      <h1>Hello World</h1>
                      <p>Java running in Docker</p>
                      <p>Java <code>%s</code> &middot; container <code>%s</code></p>
                    </div></body></html>
                    """.formatted(System.getProperty("java.version"), host);

            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
            exchange.sendResponseHeaders(200, bytes.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(bytes);
            }
        });

        server.createContext("/health", exchange -> {
            byte[] bytes = "{\"status\":\"ok\",\"app\":\"java\"}".getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, bytes.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(bytes);
            }
        });

        server.setExecutor(Executors.newFixedThreadPool(4));
        server.start();
        System.out.println("Java Hello World listening on port " + PORT);
    }
}
