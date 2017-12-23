package conf

import (
	"encoding/json"
	"io/ioutil"
)

// SpoonConfigAgent is a sub structure of SpoonConfig
type SpoonConfigAgent struct {
	Enabled  bool                   `json:"enabled"`
	Type     string                 `json:"type"`
	Interval float32                `json:"interval"`
	Path     string                 `json:"path"`
	Settings map[string]interface{} `json:"settings"`
}

// SpoonConfigSink is a sub structure of SpoonConfig
type SpoonConfigSink struct {
	Type     string                 `json:"type"`
	Settings map[string]interface{} `json:"settings"`
}

// SpoonConfig is the definition of the json config structure
type SpoonConfig struct {
	BasePath string             `json:"base_path"`
	Agents   []SpoonConfigAgent `json:"agents"`
	Sink     SpoonConfigSink    `json:"sink"`
}

// Load the config information from the file on disk
func Load(path *string) (*SpoonConfig, error) {

	// first read all bytes from file
	data, err := ioutil.ReadFile(*path)
	if err != nil {
		return nil, err
	}

	// now parse config object out
	var cfg SpoonConfig
	err = json.Unmarshal(data, &cfg)
	if err != nil {
		return nil, err
	}

	// and return
	return &cfg, nil
}
