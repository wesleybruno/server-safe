package modules

import (
	"context"
	"fmt"

	"server-safe/internal/keystore"
	"server-safe/internal/runner"
	"server-safe/internal/scripts"
)

type CreateUserRequest struct {
	Username    string `json:"username"`
	GenerateKey bool   `json:"generate_key"`
	PublicKey   string `json:"public_key,omitempty"`
}

type CreateUserOutcome struct {
	Result   *runner.Result `json:"result"`
	KeyToken string         `json:"key_token,omitempty"`
}

// CreateUser creates (or reuses) a sudo-capable user and installs an SSH
// public key. When req.GenerateKey is true, a new keypair is generated into
// a tmpfs directory and KeyToken is returned so the caller can expose a
// one-time download link; the private key never touches persistent disk.
func CreateUser(ctx context.Context, ks *keystore.Store, req CreateUserRequest, onLine func(string)) (*CreateUserOutcome, error) {
	env := []string{
		"PATH=/usr/bin:/bin:/usr/sbin:/sbin",
		"SS_USERNAME=" + req.Username,
	}

	var keyToken string
	if req.GenerateKey {
		token, err := keystore.GenToken()
		if err != nil {
			return nil, fmt.Errorf("gerar token: %w", err)
		}
		dir, err := ks.NewDir(token)
		if err != nil {
			return nil, fmt.Errorf("criar dir tmpfs: %w", err)
		}
		keyToken = token
		env = append(env, "SS_GENERATE_KEY=true", "SS_KEY_OUT_DIR="+dir)
	} else {
		env = append(env, "SS_GENERATE_KEY=false", "SS_PUBLIC_KEY="+req.PublicKey)
	}

	res, err := runner.Run(ctx, scripts.Combine(scripts.UserCreate), nil, env, onLine)
	if err != nil && res == nil {
		return nil, err
	}

	return &CreateUserOutcome{Result: res, KeyToken: keyToken}, nil
}
