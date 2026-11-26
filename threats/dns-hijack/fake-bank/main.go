// a fake login page for the dns demo; submitted creds just go to a local file
package main

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"
)

const loginPage = `<!doctype html>
<html><head><title>Bank-Lab (FICTIONAL - lab only)</title></head>
<body style="font-family:sans-serif;max-width:420px;margin:60px auto">
<h2>Bank-Lab Online</h2>
<p style="color:#b00">FICTIONAL demo site for a security lab. Not a real bank. Do not enter real credentials.</p>
<form method="POST" action="/login">
  <p><input name="username" placeholder="username" style="width:100%"></p>
  <p><input name="password" type="password" placeholder="password" style="width:100%"></p>
  <button type="submit">Sign in</button>
</form>
</body></html>`

var sinkPath = envOr("SINK_PATH", "/var/log/fake-bank/creds.log")

func main() {
	addr := envOr("LISTEN_ADDR", ":80")
	mkdirOf(sinkPath)

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, "ok") })
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		fmt.Fprint(w, loginPage)
	})
	http.HandleFunc("/login", handleLogin)

	slog.Info("fake-bank up", "addr", addr, "sink", sinkPath)
	if err := http.ListenAndServe(addr, nil); err != nil {
		panic(err)
	}
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
	r.ParseForm()
	rec := map[string]string{
		"time":     time.Now().UTC().Format(time.RFC3339),
		"username": r.FormValue("username"),
		"password": r.FormValue("password"),
		"client":   r.RemoteAddr,
	}
	if f, err := os.OpenFile(sinkPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600); err == nil {
		line, _ := json.Marshal(rec)
		fmt.Fprintln(f, string(line))
		f.Close()
	}
	slog.Info("captured credentials to local sink", "user", rec["username"], "client", rec["client"])
	fmt.Fprint(w, "<p>signed in (lab)</p>")
}

func envOr(k, d string) string {
	if v, ok := os.LookupEnv(k); ok {
		return v
	}
	return d
}

func mkdirOf(path string) {
	for i := len(path) - 1; i >= 0; i-- {
		if path[i] == '/' {
			os.MkdirAll(path[:i], 0o755)
			return
		}
	}
}
