package main

import (
	"bufio"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"time"

	proxyproto "github.com/pires/go-proxyproto"
)

type Honeypot struct {
	ports []int
}

func NewHoneypot(ports []int) *Honeypot {
	return &Honeypot{ports: ports}
}

func (hp *Honeypot) Start() {
	for _, port := range hp.ports {
		switch port {
		case 21:
			// FTP (wrapped with PROXY protocol)
			go hp.listenFTP(port)
		case 80:
			// HTTP
			go hp.startHTTP(port)
		default:
			go hp.listenOnPort(port)
		}
	}

	// Wait for interrupt to exit
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt)
	<-sig
	fmt.Println("Shutting down honeypot...")
}

func (hp *Honeypot) listenOnPort(port int) {
	addr := fmt.Sprintf("0.0.0.0:%d", port)
	ln, err := net.Listen("tcp4", addr)
	if err != nil {
		fmt.Printf("[!] Error listening on port %d: %v\n", port, err)
		return
	}
	fmt.Printf("[*] Listening on port %d\n", port)
	for {
		conn, err := ln.Accept()
		if err != nil {
			continue
		}
		go hp.handleGenericConnection(conn, port)
	}
}

func (hp *Honeypot) handleGenericConnection(conn net.Conn, port int) {
	defer conn.Close()
	remote := conn.RemoteAddr().String()
	ip, _, _ := net.SplitHostPort(remote)

	reader := bufio.NewReader(conn)
	conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	data, _ := reader.ReadString('\n')

	hp.logEvent(time.Now(), ip, port, data, nil, 0)
}

func (hp *Honeypot) listenFTP(port int) {
	addr := fmt.Sprintf("0.0.0.0:%d", port)
	ln, err := net.Listen("tcp4", addr)
	if err != nil {
		fmt.Printf("[!] Error listening on FTP port %d: %v\n", port, err)
		return
	}

	// Wrap with proxyproto listener so PROXY v1/v2 headers are parsed (nginx stream proxy)
	pl := &proxyproto.Listener{Listener: ln}
	defer pl.Close()

	fmt.Printf("[*] FTP honeypot listening on port %d (PROXY protocol enabled)\n", port)
	for {
		conn, err := pl.Accept()
		if err != nil {
			// Accept errors may occur on shutdown; continue to keep server alive
			continue
		}
		go hp.handleFTPSession(conn, port)
	}
}

func (hp *Honeypot) handleFTPSession(conn net.Conn, port int) {
	defer conn.Close()

	remote := conn.RemoteAddr().String()
	ip, _, _ := net.SplitHostPort(remote)

	start := time.Now()
	session := []string{}

	// Send welcome banner
	_, _ = conn.Write([]byte("220 FTP Service Ready\r\n"))
	reader := bufio.NewReader(conn)

	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			break
		}
		cmd := strings.TrimSpace(line)
		session = append(session, cmd)

		if strings.ToUpper(cmd) == "QUIT" {
			_, _ = conn.Write([]byte("221 Goodbye.\r\n"))
			break
		} else {
			_, _ = conn.Write([]byte("500 Unknown command.\r\n"))
		}
	}

	duration := time.Since(start)
	hp.logEvent(start, ip, port, "", session, duration)
}

func (hp *Honeypot) startHTTP(port int) {
	mux := http.NewServeMux()

	wrap := func(handler func(http.ResponseWriter, *http.Request) string) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			info := handler(w, r)

			// Prefer X-Forwarded-For if present (nginx will set this when terminating TLS).
			ip := ""
			if xf := r.Header.Get("X-Forwarded-For"); xf != "" {
				ip = strings.TrimSpace(strings.Split(xf, ",")[0])
			} else {
				ip = strings.Split(r.RemoteAddr, ":")[0]
			}

			hp.logEvent(time.Now(), ip, port, info, nil, 0)
		}
	}

	mux.HandleFunc("/search", wrap(sqlInjectionBait))
	mux.HandleFunc("/comment", wrap(xssBait))
	mux.HandleFunc("/admin.php", wrap(fakePHPAdmin))
	mux.HandleFunc("/upload", wrap(fakeUpload))
	mux.HandleFunc("/config", wrap(leakConfig))
	mux.HandleFunc("/robots.txt", wrap(serveRobots))
	mux.HandleFunc("/backup.zip", wrap(fakeDownload))
	mux.HandleFunc("/shell.php", wrap(fakeShell))

	addr := fmt.Sprintf("0.0.0.0:%d", port)
	fmt.Printf("[*] HTTP honeypot running on %s\n", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		fmt.Printf("[!] HTTP server error: %v\n", err)
	}
}

func (hp *Honeypot) logEvent(t time.Time, ip string, port int, payload string, session []string, duration time.Duration) {
	ts := t.Format(time.RFC3339)
	if len(session) > 0 {
		fmt.Printf("[FTP] %s - %s:%d session (duration=%s)\n", ts, ip, port, duration)
		for _, cmd := range session {
			fmt.Printf("\t> %s\n", cmd)
		}
	} else {
		fmt.Printf("[HTTP/GEN] %s - %s:%d > %s\n", ts, ip, port, strings.TrimSpace(payload))
	}
}

func sqlInjectionBait(w http.ResponseWriter, r *http.Request) string {
	q := r.URL.Query().Get("q")
	fmt.Fprintf(w, "Results for '%s': No results found.", q)
	return fmt.Sprintf("Search query: %s", q)
}

func xssBait(w http.ResponseWriter, r *http.Request) string {
	msg := r.URL.Query().Get("msg")
	fmt.Fprintf(w, "<p>%s</p>", msg)
	return fmt.Sprintf("XSS comment: %s", msg)
}

func fakePHPAdmin(w http.ResponseWriter, r *http.Request) string {
	if r.Method == "POST" {
		r.ParseForm()
		u := r.FormValue("user")
		p := r.FormValue("pass")
		fmt.Fprintln(w, "Access Denied.")
		return fmt.Sprintf("Admin.php login attempt: %s / %s", u, p)
	}
	fmt.Fprintln(w, `
		<!DOCTYPE html>
		<html>
		<head><title>Admin Login</title></head>
		<body>
			<h2>Admin Panel</h2>
			<form method='POST' action='admin.php'>
				User: <input name='user'/><br/>
				Pass: <input name='pass' type='password'/><br/>
				<input type='submit'/>
			</form>
		</body>
		</html>`)
	return "Admin.php login form served"
}

func fakeUpload(w http.ResponseWriter, r *http.Request) string {
	if r.Method == "POST" {
		r.ParseMultipartForm(10 << 20)
		file, handler, err := r.FormFile("upload")
		if err == nil {
			file.Close()
			fmt.Fprintln(w, "File received.")
			return fmt.Sprintf("File uploaded: %s (%d bytes)", handler.Filename, handler.Size)
		}
		fmt.Fprintln(w, "Upload failed.")
		return "Upload error"
	}
	fmt.Fprintln(w, "<form method='POST' enctype='multipart/form-data'>File: <input type='file' name='upload'/><br/><input type='submit'/></form>")
	return "Upload form served"
}

func leakConfig(w http.ResponseWriter, r *http.Request) string {
	fmt.Fprintln(w, "DB_PASS=supersecret\nAPI_KEY=12345-ABCDE")
	return "Config file accessed"
}

func serveRobots(w http.ResponseWriter, r *http.Request) string {
	fmt.Fprintln(w, "User-agent: *\nDisallow: /backup\nDisallow: /admin")
	return "robots.txt requested"
}

func fakeDownload(w http.ResponseWriter, r *http.Request) string {
	w.Header().Set("Content-Disposition", "attachment; filename=backup.zip")
	w.Write([]byte("FAKE_ZIP_CONTENT"))
	return "Backup.zip requested"
}

func fakeShell(w http.ResponseWriter, r *http.Request) string {
	cmd := r.URL.Query().Get("cmd")
	fmt.Fprintf(w, "Output: %s", strings.Repeat("*", len(cmd)))
	return fmt.Sprintf("Web shell command: %s", cmd)
}

func main() {
	// run HTTP and FTP
	hp := NewHoneypot([]int{80, 21})
	hp.Start()
}
