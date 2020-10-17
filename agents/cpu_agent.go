package agents

import (
	"fmt"
	"runtime"
	"time"

	"github.com/shirou/gopsutil/cpu"

	"github.com/astromechza/spoon-oci/conf"
	"github.com/astromechza/spoon-oci/sink"
)

type cpuAgent struct {
	config conf.SpoonConfigAgent

	// some cpu vars to track cpu change
	numCPU        int
	hasPrevCPU    bool
	prevCPUTime   time.Time
	prevCPUTotals []float64
	prevCPUBusys  []float64
}

func NewCPUAgent(config *conf.SpoonConfigAgent) (Agent, error) {
	return &cpuAgent{
		config:     (*config),
		numCPU:     runtime.NumCPU(),
		hasPrevCPU: false,
	}, nil
}

func (a *cpuAgent) GetConfig() conf.SpoonConfigAgent {
	return a.config
}

func (a *cpuAgent) Tick(s sink.Sink) error {

	now := time.Now()
	cpuTimesSet, err := cpu.Times(true)
	if err != nil {
		return err
	}

	totals := make([]float64, len(cpuTimesSet))
	busys := make([]float64, len(cpuTimesSet))
	for i, ts := range cpuTimesSet {
		// calculate and store total
		totals[i] = ts.Total()
		busys[i] = totals[i] - ts.Idle

		// if we have a previous total for this cpu
		if a.hasPrevCPU && len(a.prevCPUTotals) > i {
			percent := a.calculateCPUPercent(a.prevCPUTotals[i], totals[i], a.prevCPUBusys[i], busys[i])
			subpath := fmt.Sprintf("%s.%v.cpu_percent", a.config.Path, i)
			s.Gauge(subpath, percent)
		}
	}

	a.hasPrevCPU = true
	a.prevCPUBusys = busys
	a.prevCPUTotals = totals
	a.prevCPUTime = now

	return nil
}

func (a *cpuAgent) calculateCPUPercent(t1t, t2t, t1b, t2b float64) float64 {
	if t2b <= t1b {
		return 0
	}
	if t2t <= t1t {
		return 1
	}
	return ((t2b - t1b) / (t2t - t1t)) * 100
}
