package createpod_test

import (
	"fmt"
	"github.com/kyma-project/istio/operator/tests/e2e/e2e/setup"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestPodCreation(t *testing.T) {
	testId := setup.GenerateRandomTestId()
	namespaceName := fmt.Sprintf("test-%s", testId)
	k8sClient, err := setup.ClientFromKubeconfig(t)
	if err != nil {
		t.Fatal(err)
	}
	err = setup.CreateNamespace(t, k8sClient, namespaceName)
	if err != nil {
		t.Fatal(err)
	}

	t.Run("test1", func(t *testing.T) {
		subtestId := setup.GenerateRandomTestId()
		podName := fmt.Sprintf("test-%s", subtestId)
		t.Parallel()

		// given
		pod := &corev1.Pod{
			ObjectMeta: metav1.ObjectMeta{
				Namespace: namespaceName,
				Name:      podName,
			},
			Spec: corev1.PodSpec{
				Containers: []corev1.Container{
					{
						Name:  "test-container",
						Image: "nginx:latest",
						Ports: []corev1.ContainerPort{
							{
								ContainerPort: 80,
								Name:          "http",
							},
						},
					},
				},
			},
		}

		// when
		err := createPod(t, k8sClient, pod)

		// then
		require.NoError(t, err)

		retrievedPod, err := getPod(t, k8sClient, namespaceName, podName)
		require.NoError(t, err)
		assert.NotNil(t, retrievedPod)
	})

	t.Run("test2", func(t *testing.T) {
		subtestId := setup.GenerateRandomTestId()
		podName := fmt.Sprintf("test-%s", subtestId)
		t.Parallel()

		// given
		pod := &corev1.Pod{
			ObjectMeta: metav1.ObjectMeta{
				Namespace: namespaceName,
				Name:      podName,
			},
			Spec: corev1.PodSpec{
				Containers: []corev1.Container{
					{
						Name:  "test-container",
						Image: "nginx:latest",
						Ports: []corev1.ContainerPort{
							{
								ContainerPort: 80,
								Name:          "http",
							},
						},
					},
				},
			},
		}

		// when
		t.Logf("Creating pod %s", podName)
		err := createPod(t, k8sClient, pod)

		// then
		require.NoError(t, err)

		retrievedPod, err := getPod(t, k8sClient, namespaceName, podName)
		require.NoError(t, err)
		assert.NotNil(t, retrievedPod)
	})
}

func createPod(t *testing.T, k8sClient client.Client, pod *corev1.Pod) error {
	setup.DeclareCleanup(t, func() {
		t.Logf("Cleaning Pod: %+v", *pod)
		err := k8sClient.Delete(setup.GetCleanupContext(), pod)
		if err != nil {
			t.Logf("Failed to delete pod %s/%s: %v", pod.Namespace, pod.Name, err)
		}
	})

	t.Logf("Creating Pod: %+v", *pod)
	err := k8sClient.Create(t.Context(), pod)
	if err != nil {
		return fmt.Errorf("failed to create pod: %w", err)
	}
	return nil
}

func getPod(t *testing.T, k8sClient client.Client, namespaceName string, name string) (*corev1.Pod, error) {
	pod := &corev1.Pod{}
	t.Logf("Getting Pod: name: %s, namespace: %s", name, namespaceName)
	err := k8sClient.Get(t.Context(), types.NamespacedName{Namespace: namespaceName, Name: name}, pod)
	if err != nil {
		return nil, err
	}
	return pod, nil
}
