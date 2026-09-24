package factory

type LB interface {
	Annotations() map[string]string
}

type CNI interface {
	CNIValues() map[string]interface{}
}

type Inputs struct {
	DualStackFullyEnabled bool
	DualStackLBEnabled    bool
	UsesGardenOS          bool
}

type Factory interface {
	LB() LB
	CNI() CNI
	NeedsProxyProtocol() bool
	DualStackFullyEnabled() bool
}

type defaultFactory struct {
	inputs Inputs
}

// DefaultFactory is the fallback Factory for unknown cluster providers.
// It produces no LB or CNI customizations but reports the cluster's
// DualStackEnabled flag.
func DefaultFactory(in Inputs) Factory {
	return &defaultFactory{inputs: in}
}

func (f *defaultFactory) LB() LB                      { return nil }
func (f *defaultFactory) CNI() CNI                    { return nil }
func (f *defaultFactory) NeedsProxyProtocol() bool    { return false }
func (f *defaultFactory) DualStackFullyEnabled() bool { return f.inputs.DualStackFullyEnabled }
