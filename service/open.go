package service

import (
	"bytes"
	"net/url"
	"regexp"
	"strconv"
	"text/template"

	"github.com/nats-io/nats.go"
)

type Script struct {
	Client         string
	QuotedFilename string
	Selection      Selection
}

type Selection struct {
	Start, End Position
}

type Position struct {
	Line, Column int
}

var templ = template.Must(template.New("script").Parse(`
  evaluate-commands -try-client {{.Client}} %{
    try %{
      edit -existing {{.QuotedFilename}}
      try focus
    } catch %{
      echo -markup "{Error}%val{error}"
      echo -debug "%val{error}"
    }
  }
`))

var fragmentRegexp = regexp.MustCompile(`^line=(\d+)`)

func (s Script) String() string {
	buf := &bytes.Buffer{}
	_ = templ.Execute(buf, s)
	return buf.String()
}

type OpenCmd struct {
	Session string
	Script  Script
}

func quote(s string) string {
	result := "'"
	for _, ch := range s {
		if ch == '\'' {
			result += "'"
		}
		result += string(ch)
	}
	return result + "'"
}

func (s *Service) OpenCommand(msg *nats.Msg) OpenCmd {
	u, _ := url.Parse(string(msg.Data))
	result := OpenCmd{
		Session: "kakoune",
		Script: Script{
			Client:         "%opt{jumpclient}",
			QuotedFilename: quote(u.Path),
			Selection: Selection{
				Start: Position{1, 1},
				End:   Position{1, 1},
			},
		},
	}
	if match := fragmentRegexp.FindStringSubmatch(u.Fragment); match != nil {
		line, _ := strconv.ParseInt(match[1], 10, 64)
		result.Script.Selection = Selection{
			Start: Position{int(line) + 1, 1},
			End:   Position{int(line) + 1, 1},
		}
	}
	if s := msg.Header.Get("Session"); s != "" {
		result.Session = s
	}
	if w := msg.Header.Get("Window"); w != "" {
		result.Script.Client = quote(w)
	}
	return result
}
