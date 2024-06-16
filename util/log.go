package util

import (
	"io"
	"log"
	"os"
)

const (
	TRACE uint = iota
	DEBUG
	INFO
	WARN
	ERROR
	FATAL
	PANIC
)

var LOG_STDERR = log.New(os.Stderr, "", 0)

var LOG_TRACE = log.New(io.Discard, "", log.Lshortfile)
var LOG_DEBUG = log.New(io.Discard, "", log.Lshortfile)
var LOG_INFO = log.New(io.Discard, "", log.Lshortfile)
var LOG_WARN = log.New(io.Discard, "", log.Lshortfile)
var LOG_ERROR = log.New(io.Discard, "", log.Lshortfile)
var LOG_FATAL = log.New(io.Discard, "", log.Lshortfile)
var LOG_PANIC = log.New(io.Discard, "", log.Lshortfile)

func Set_log_level(log_level string) {
	var level uint = 0
	switch log_level {
	case "trace":
		level = TRACE
	case "debug":
		level = DEBUG
	case "info":
		level = INFO
	case "warn":
		level = WARN
	case "error":
		level = ERROR
	case "fatal":
		level = FATAL
	case "panic":
		level = PANIC
	default:
		level = ERROR
	}

	if level >= TRACE {
		LOG_TRACE = log.New(os.Stderr, "TRACE: ", log.Lshortfile)
	}
	if level >= DEBUG {
		LOG_DEBUG = log.New(os.Stderr, "DEBUG: ", log.Lshortfile)
	}
	if level >= INFO {
		LOG_INFO = log.New(os.Stderr, "INFO: ", log.Lshortfile)
	}
	if level >= WARN {
		LOG_WARN = log.New(os.Stderr, "WARN: ", log.Lshortfile)
	}
	if level >= ERROR {
		LOG_ERROR = log.New(os.Stderr, "", log.Lshortfile)
	}
	if level >= FATAL {
		LOG_FATAL = log.New(os.Stderr, "", log.Lshortfile)
	}
	if level >= PANIC {
		LOG_PANIC = log.New(os.Stderr, "", log.Lshortfile)
	}

	if ERROR == level && "error" != log_level {
		LOG_WARN.Printf("Invalid LOG_LEVEL set %q. Defaulting to LOG_LEVEL=\"error\"\n", log_level)
	}
}
