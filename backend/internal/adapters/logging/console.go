package logging

import (
	"io"
	"log/slog"

	"github.com/lmittmann/tint"
)

// NewTextHandler ใช้รูปแบบและสีมาตรฐานของ tint โดยคงตัวเลือก slog และการปิดสีเมื่อส่งออกไฟล์
func NewTextHandler(output io.Writer, options *slog.HandlerOptions, useColor bool) slog.Handler {
	cfg := &tint.Options{NoColor: !useColor}
	if options != nil {
		cfg.AddSource = options.AddSource
		cfg.Level = options.Level
		cfg.ReplaceAttr = options.ReplaceAttr
	}
	return tint.NewTextHandler(output, cfg)
}
