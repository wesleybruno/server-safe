// Package web embeds the static wizard UI into the binary.
package web

import "embed"

//go:embed index.html app.js style.css
var Files embed.FS
