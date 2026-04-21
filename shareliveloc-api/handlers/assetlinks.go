package handlers

import (
	"encoding/json"
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
)

const defaultPackageName = "com.ombapit.shareliveloc"

// AssetLinks serves /.well-known/assetlinks.json for Android App Links
// verification. Fingerprints come from the APP_SHA256_FINGERPRINTS env
// var (comma-separated) so you can update without redeploying code when
// you get them from Play Console -> App integrity -> App signing.
func AssetLinks(c *gin.Context) {
	pkg := os.Getenv("APP_PACKAGE_NAME")
	if pkg == "" {
		pkg = defaultPackageName
	}

	raw := os.Getenv("APP_SHA256_FINGERPRINTS")
	fingerprints := []string{}
	if raw != "" {
		for _, f := range strings.Split(raw, ",") {
			f = strings.TrimSpace(f)
			f = strings.Trim(f, "\"'")
			if f != "" {
				fingerprints = append(fingerprints, f)
			}
		}
	}

	payload := []map[string]interface{}{
		{
			"relation": []string{"delegate_permission/common.handle_all_urls"},
			"target": map[string]interface{}{
				"namespace":                 "android_app",
				"package_name":              pkg,
				"sha256_cert_fingerprints": fingerprints,
			},
		},
	}

	data, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.Data(http.StatusOK, "application/json", data)
}
