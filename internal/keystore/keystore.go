// Package keystore manages short-lived, RAM-backed (tmpfs) directories that
// hold generated SSH private keys until the user downloads them once, or
// until a TTL expires — the key material must never persist on real disk.
package keystore

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

type entry struct {
	dir        string
	downloaded bool
	expiresAt  time.Time
}

type Store struct {
	mu      sync.Mutex
	entries map[string]*entry
	baseDir string
	ttl     time.Duration
}

// New creates a store rooted at baseDir (expected to be tmpfs, e.g.
// /dev/shm/server-safe) and starts a background sweeper that wipes entries
// past their TTL even if never downloaded.
func New(baseDir string, ttl time.Duration) *Store {
	_ = os.MkdirAll(baseDir, 0700)
	s := &Store{
		entries: make(map[string]*entry),
		baseDir: baseDir,
		ttl:     ttl,
	}
	go s.sweepLoop()
	return s
}

// GenToken returns a random hex token used both as the map key and the
// on-disk directory name.
func GenToken() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// NewDir creates a fresh tmpfs directory for token and registers its TTL.
func (s *Store) NewDir(token string) (string, error) {
	dir := filepath.Join(s.baseDir, token)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return "", err
	}
	s.mu.Lock()
	s.entries[token] = &entry{dir: dir, expiresAt: time.Now().Add(s.ttl)}
	s.mu.Unlock()
	return dir, nil
}

// KeyPath returns the private key path for token if it still exists, has
// not expired, and has not already been downloaded.
func (s *Store) KeyPath(token string) (string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.entries[token]
	if !ok || e.downloaded || time.Now().After(e.expiresAt) {
		return "", false
	}
	return filepath.Join(e.dir, "id_ed25519"), true
}

// MarkDownloaded flags token as served and schedules its wipe shortly after,
// giving the in-flight HTTP response time to finish writing the file.
func (s *Store) MarkDownloaded(token string) {
	s.mu.Lock()
	e, ok := s.entries[token]
	if ok {
		e.downloaded = true
	}
	s.mu.Unlock()
	if !ok {
		return
	}
	time.AfterFunc(5*time.Second, func() { s.wipe(token, e) })
}

func (s *Store) sweepLoop() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		now := time.Now()
		s.mu.Lock()
		expired := make(map[string]*entry)
		for token, e := range s.entries {
			if now.After(e.expiresAt) {
				expired[token] = e
			}
		}
		s.mu.Unlock()
		for token, e := range expired {
			s.wipe(token, e)
		}
	}
}

func (s *Store) wipe(token string, e *entry) {
	s.mu.Lock()
	delete(s.entries, token)
	s.mu.Unlock()

	files, err := os.ReadDir(e.dir)
	if err == nil {
		for _, f := range files {
			p := filepath.Join(e.dir, f.Name())
			if err := exec.Command("shred", "-u", "-f", p).Run(); err != nil {
				_ = os.Remove(p)
			}
		}
	}
	if err := os.Remove(e.dir); err != nil && !os.IsNotExist(err) {
		log.Printf("keystore: falha removendo %s: %v", e.dir, err)
	}
}
