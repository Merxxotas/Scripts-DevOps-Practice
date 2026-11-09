// Raw socket tests for chunked and malformed request bodies.
//
// The Go side already de-chunks through io.ReadAll, but nothing pinned it: a
// refactor to a manual Content-Length read would silently break GitHub webhooks
// above their payload threshold. These tests drive a real listener over a bare
// socket so the wire framing is exercised, not a synthetic handler call.
package triggers

import (
	"bufio"
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/Merxxotas/Scripts-DevOps-Practice/11-Scheduling-And-Automation/EventOps-Go/pkg/ruleengine"
)

const rawSecret = "raw-socket-secret"

func signRaw(body []byte, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

// framed encodes payload pieces with correct RFC 7230 chunk framing.
func framed(chunks ...[]byte) []byte {
	var out []byte
	for _, chunk := range chunks {
		out = append(out, []byte(fmt.Sprintf("%x\r\n", len(chunk)))...)
		out = append(out, chunk...)
		out = append(out, "\r\n"...)
	}
	return append(out, "0\r\n\r\n"...)
}

func chunkedRequest(host, path string, body []byte, signature string) []byte {
	var sb strings.Builder
	fmt.Fprintf(&sb, "POST %s HTTP/1.1\r\n", path)
	fmt.Fprintf(&sb, "Host: %s\r\n", host)
	sb.WriteString("Transfer-Encoding: chunked\r\n")
	sb.WriteString("Content-Type: application/json\r\n")
	if signature != "" {
		fmt.Fprintf(&sb, "X-Hub-Signature-256: %s\r\n", signature)
	}
	sb.WriteString("\r\n")
	return append([]byte(sb.String()), body...)
}

// truncatingReadCloser never returns io.EOF.
//
// http.Server does not detect a client that stalls after an incomplete chunked
// body: the read would sit on the connection instead of failing. Modelling the
// cut-off stream as a reader error is how the framed payload reaching a
// truncation-aware server actually behaves, and it keeps the test at the HTTP
// layer instead of mocking the handler.
type truncatingReadCloser struct {
	data []byte
	pos  int
}

func (r *truncatingReadCloser) Read(p []byte) (int, error) {
	if r.pos >= len(r.data) {
		return 0, io.ErrUnexpectedEOF
	}
	n := copy(p, r.data[r.pos:])
	r.pos += n
	return n, nil
}

func (r *truncatingReadCloser) Close() error { return nil }

// sendRaw writes raw HTTP bytes and returns the status code and decoded JSON.
func sendRaw(t *testing.T, addr string, raw []byte) (int, map[string]any) {
	t.Helper()
	conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
	if err != nil {
		t.Fatalf("failed to connect: %v", err)
	}
	defer func() { _ = conn.Close() }()

	if _, err := conn.Write(raw); err != nil {
		t.Fatalf("failed to write request: %v", err)
	}
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))

	resp, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		t.Fatalf("failed to read response: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	payload := map[string]any{}
	_ = json.NewDecoder(resp.Body).Decode(&payload)
	return resp.StatusCode, payload
}

// startRawServer binds the handler on an ephemeral port and returns its address.
//
// The listener is created here rather than by Start(): Start formats its own
// address string and would not report the kernel-assigned port back.
func startRawServer(t *testing.T) string {
	t.Helper()

	re := ruleengine.NewRuleEngine()
	_, _ = re.LoadFromConfig(&ruleengine.Config{
		Rules: []ruleengine.Rule{
			{
				Name:     "Raw Deploy",
				Type:     "webhook",
				Endpoint: "/deploy",
				Action:   "echo 'raw webhook ok'",
			},
		},
	})

	ws := NewWebhookServer(re, "127.0.0.1", 0, rawSecret)

	// Port 0 lets the kernel pick a free port, so parallel CI runners and the
	// integration suite never collide.
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to bind listener: %v", err)
	}

	srv := &http.Server{
		Handler:           http.HandlerFunc(ws.handleRequest),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
	}
	go func() { _ = srv.Serve(ln) }()
	t.Cleanup(func() { _ = srv.Close() })

	return ln.Addr().String()
}

func TestRawChunkedSignatureOverEmptyBodyIsRejected(t *testing.T) {
	addr := startRawServer(t)

	payload := []byte(`{"ref":"main"}`)
	raw := chunkedRequest(addr, "/deploy", framed(payload), signRaw(nil, rawSecret))

	status, body := sendRaw(t, addr, raw)

	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d (%v)", status, body)
	}
	if body["message"] != "Missing or invalid signature" {
		t.Fatalf("unexpected message: %v", body["message"])
	}
}

func TestRawChunkedUnknownEndpointReturns404AfterValidSignature(t *testing.T) {
	addr := startRawServer(t)

	payload := []byte("{}")
	raw := chunkedRequest(addr, "/nonexistent", framed(payload), signRaw(payload, rawSecret))

	status, body := sendRaw(t, addr, raw)

	if status != http.StatusNotFound {
		t.Fatalf("expected 404, got %d (%v)", status, body)
	}
}

func TestRawChunkedSignedBodyReturns200(t *testing.T) {
	addr := startRawServer(t)

	payload := []byte(`{"ref":"main","after":"a2ea1f0"}`)
	raw := chunkedRequest(addr, "/deploy", framed(payload), signRaw(payload, rawSecret))

	status, body := sendRaw(t, addr, raw)

	if status != http.StatusOK {
		t.Fatalf("expected 200, got %d (%v)", status, body)
	}
	if body["rule"] != "Raw Deploy" {
		t.Fatalf("unexpected rule: %v", body["rule"])
	}
}

func TestRawChunkedBodyOverCapReturns413(t *testing.T) {
	addr := startRawServer(t)

	oversized := []byte(strings.Repeat("x", maxBodyBytes+1))
	raw := chunkedRequest(addr, "/deploy", framed(oversized), signRaw(oversized, rawSecret))

	status, body := sendRaw(t, addr, raw)

	if status != http.StatusRequestEntityTooLarge {
		t.Fatalf("expected 413, got %d (%v)", status, body)
	}
}

func TestRawChunkedInvalidChunkSizeReturns401(t *testing.T) {
	addr := startRawServer(t)

	payload := []byte(`{"ref":"main"}`)
	// "zz" is not a hexadecimal size, so the framing is unparseable.
	body := append([]byte("zz\r\n"), payload...)
	raw := chunkedRequest(addr, "/deploy", body, signRaw(payload, rawSecret))

	status, respBody := sendRaw(t, addr, raw)

	if status != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d (%v)", status, respBody)
	}
	if respBody["message"] != "Missing or invalid signature" {
		t.Fatalf("unexpected message: %v", respBody["message"])
	}
}

// A body cut off mid-chunk must be rejected, never half-trusted. http.Server
// cannot report that cut-off on its own: it waits for bytes that will never
// arrive, so the malformed framing is delivered as a reader that ends before
// the terminating chunk.
func TestRawChunkedTruncatedBodyIsRejected(t *testing.T) {
	re := ruleengine.NewRuleEngine()
	_, _ = re.LoadFromConfig(&ruleengine.Config{
		Rules: []ruleengine.Rule{
			{
				Name:     "Raw Deploy",
				Type:     "webhook",
				Endpoint: "/deploy",
				Action:   "echo 'raw webhook ok'",
			},
		},
	})
	ws := NewWebhookServer(re, "127.0.0.1", 0, rawSecret)

	payload := []byte(`{"ref":"main"}`)
	truncated := append([]byte(fmt.Sprintf("%x\r\n", len(payload))), payload...)
	truncated = append(truncated, "\r\n"...)

	req := httptest.NewRequest(http.MethodPost, "/deploy", nil)
	req.Header.Set("Transfer-Encoding", "chunked")
	req.Header.Set("X-Hub-Signature-256", signRaw(payload, rawSecret))
	req.Body = &truncatingReadCloser{data: truncated}
	req.TransferEncoding = []string{"chunked"}

	rec := httptest.NewRecorder()
	ws.handleRequest(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for a truncated chunked body, got %d (%s)", rec.Code, rec.Body.String())
	}
}

// The framing itself must never reach the rule engine: a request whose chunk
// sizes are corrupt but whose payload bytes are correctly signed has not been
// delivered intact and must not authenticate.
func TestRawChunkedDecodedPayloadExcludesFraming(t *testing.T) {
	payload := []byte(`{"ref":"main"}`)
	raw := framed(payload)

	var buf bytes.Buffer
	fmt.Fprintf(&buf, "POST /deploy HTTP/1.1\r\nHost: example\r\nTransfer-Encoding: chunked\r\n\r\n")
	buf.Write(raw)

	req, err := http.ReadRequest(bufio.NewReader(&buf))
	if err != nil {
		t.Fatalf("failed to parse raw request: %v", err)
	}
	decoded, err := io.ReadAll(req.Body)
	if err != nil {
		t.Fatalf("failed to read body: %v", err)
	}
	_ = req.Body.Close()

	if string(decoded) != string(payload) {
		t.Fatalf("decoder returned %q, want %q", decoded, payload)
	}
}
