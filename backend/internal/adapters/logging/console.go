package logging

import (
	"io"
	"log/slog"
	"regexp"
	"strconv"
	"strings"
)

const (
	colorGreen  = "\x1b[32m"
	colorYellow = "\x1b[33m"
	colorRed    = "\x1b[31m"
	colorReset  = "\x1b[0m"
)

// แยกค่าที่มีเครื่องหมายคำพูดทั้งก้อน เพื่อไม่ใส่สีให้ข้อความที่บังเอิญมี status= หรือ level=
var textFields = regexp.MustCompile(`"(?:\\.|[^"\\])*"|[^\s"]+`)

// NewTextHandler คงรูปแบบ slog เดิม และใส่สีเฉพาะสถานะ HTTP กับระดับคำเตือนหรือข้อผิดพลาด
func NewTextHandler(output io.Writer, options *slog.HandlerOptions, useColor bool) slog.Handler {
	if useColor {
		output = &consoleWriter{output: output}
	}
	return slog.NewTextHandler(output, options)
}

type consoleWriter struct {
	output io.Writer
}

func (w *consoleWriter) Write(data []byte) (int, error) {
	colored := textFields.ReplaceAllFunc(data, func(field []byte) []byte {
		key, value, _ := strings.Cut(string(field), "=")
		color := ""
		switch key {
		case "status":
			status, err := strconv.Atoi(value)
			if err != nil {
				return field
			}
			switch {
			case status >= 200 && status < 300:
				color = colorGreen
			case status >= 400 && status < 500:
				color = colorYellow
			case status >= 500 && status < 600:
				color = colorRed
			}
		case "level":
			switch value {
			case "WARN":
				color = colorYellow
			case "ERROR":
				color = colorRed
			}
		}
		if color == "" {
			return field
		}
		return []byte(color + string(field) + colorReset)
	})
	if n, err := w.output.Write(colored); err != nil {
		return 0, err
	} else if n != len(colored) {
		return 0, io.ErrShortWrite
	}
	return len(data), nil
}
