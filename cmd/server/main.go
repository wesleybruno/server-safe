// Command server-safe is a self-contained wizard for the initial hardening
// of a fresh Linux box: it serves a local web UI and executes embedded bash
// modules (user creation, SSH lockdown, firewall, fail2ban, ...) as root.
package main

import (
	"context"
	"flag"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"server-safe/internal/api"
	"server-safe/internal/keystore"
	"server-safe/web"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:8080", "endereco de escuta (host:porta)")
	keyDir := flag.String("keydir", "/dev/shm/server-safe", "diretorio tmpfs para chaves privadas temporarias")
	keyTTL := flag.Duration("key-ttl", 15*time.Minute, "tempo max que uma chave gerada fica disponivel para download")
	flag.Parse()

	if os.Geteuid() != 0 {
		log.Println("aviso: nao esta rodando como root — a maioria dos modulos vai falhar")
	}

	ks := keystore.New(*keyDir, *keyTTL)

	webFS, err := fs.Sub(web.Files, ".")
	if err != nil {
		log.Fatalf("erro montando assets web: %v", err)
	}

	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.FS(webFS)))
	api.RegisterRoutes(mux, ks)

	srv := &http.Server{Addr: *addr, Handler: mux}

	go func() {
		log.Printf("server-safe ouvindo em http://%s", *addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("erro no servidor: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	log.Println("encerrando...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
}
