package createnamespacewithkubectl_test

import (
	"github.com/kyma-project/istio/operator/tests/e2e/e2e/setup"
	"os/exec"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestCreateNsWithKubectl(t *testing.T) {
	t.Parallel()

	t.Run("Create Namespace", func(t *testing.T) {
		t.Parallel()

		output, err := createNamespace(t, "test-namespace")
		require.NoError(t, err)
		require.Contains(t, string(output), "namespace/test-namespace created", "Expected namespace creation confirmation in output")

		// Verify Namespace Creation
		output, err = getNamespace(t, "test-namespace")
		t.Logf("Get namespace output: %s", string(output))
		require.NoError(t, err, "Namespace should be fetched successfully")
		require.Contains(t, string(output), "test-namespace", "Expected namespace 'test-namespace' to be present in the output")
		t.Logf("Namespace created successfully: %s", output)
	})
}

func createNamespace(t *testing.T, name string) ([]byte, error) {
	setup.DeclareCleanup(t, func() {
		t.Logf("Deleting namespace: %s", name)
		output, err := exec.Command("kubectl", "delete", "namespace", name).CombinedOutput()
		if err != nil {
			t.Logf("Error deleting namespace: %s, output: %s, error: %s", name, string(output), err)
		}
	})

	t.Logf("Creating Namespace: %s", name)
	return exec.Command("kubectl", "create", "namespace", name).CombinedOutput()
}

func getNamespace(t *testing.T, name string) ([]byte, error) {
	t.Logf("Getting namespace: %s", name)
	return exec.Command("kubectl", "get", "namespace", name, "--no-headers", "-o", "custom-columns=NAME:.metadata.name").CombinedOutput()
}
