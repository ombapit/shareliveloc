package handlers

import (
	"fmt"
	"html"
	"net/http"

	"github.com/gin-gonic/gin"
)

const playStoreURL = "https://play.google.com/store/apps/details?id=com.ombapit.shareliveloc"

// OpenGroupLink serves an HTML page that tries to open the ShareLiveLoc
// app via custom scheme, falling back to Play Store if not installed.
// Used for shareable https links (WhatsApp, Telegram, etc. only make
// http/https clickable).
func OpenGroupLink(c *gin.Context) {
	group := c.Query("group")
	if group == "" {
		c.String(http.StatusBadRequest, "missing group param")
		return
	}

	safeGroup := html.EscapeString(group)
	deepLink := fmt.Sprintf("shareliveloc://group/%s", safeGroup)

	htmlPage := fmt.Sprintf(`<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>ShareLiveLoc - %s</title>
<style>
  body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#EFEAE2;margin:0;padding:0;min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:32px}
  .logo{width:96px;height:96px;background:#008069;border-radius:24px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:48px;margin-bottom:16px;box-shadow:0 8px 16px rgba(0,0,0,0.15)}
  h1{color:#008069;margin:8px 0;font-size:22px}
  p{color:#444;max-width:320px;line-height:1.5}
  .group{background:#fff;border:1px solid #ddd;border-radius:8px;padding:8px 16px;display:inline-block;font-weight:600;color:#008069;margin:8px 0}
  .btn{display:inline-block;background:#008069;color:#fff;padding:14px 32px;border-radius:24px;text-decoration:none;font-weight:600;margin-top:12px;min-width:200px}
  .btn.secondary{background:#fff;color:#008069;border:1px solid #008069;margin-top:8px}
  .hint{color:#888;font-size:12px;margin-top:16px}
</style>
</head>
<body>
  <div class="logo">📍</div>
  <h1>ShareLiveLoc</h1>
  <p>Bergabung ke grup:</p>
  <div class="group">%s</div>
  <a class="btn" href="%s" id="openApp">Buka Aplikasi</a>
  <a class="btn secondary" href="%s">Install dari Play Store</a>
  <p class="hint">Jika aplikasi tidak terbuka otomatis, tap "Buka Aplikasi" di atas.</p>
  <script>
    // Auto attempt to open the app immediately
    setTimeout(function(){
      window.location.href = %q;
    }, 100);
  </script>
</body>
</html>`, safeGroup, safeGroup, deepLink, playStoreURL, deepLink)

	c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(htmlPage))
}
