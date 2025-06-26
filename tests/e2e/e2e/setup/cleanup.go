package setup

import (
	"context"
	"os"
	"testing"
)

var shouldSkipCleanup = os.Getenv("SKIP_CLEANUP") == "true"

func ShouldSkipCleanup(t *testing.T) bool {
	return t.Failed() && shouldSkipCleanup
}

func DeclareCleanup(t *testing.T, f func()) {
	t.Cleanup(func() {
		if ShouldSkipCleanup(t) {
			t.Logf("Tests failed, skipping cleanup")
			return
		}
		f()
	})
}

func GetCleanupContext() context.Context {
	return context.Background()
}
