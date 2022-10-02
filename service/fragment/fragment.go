package fragment

import (
	"errors"
	"fmt"
	"regexp"
	"strconv"
)

type Offset = int

type LinePosition struct {
	Line, Column Offset
}

type TextPlainFragmentIdentifier struct {
	Start, End LinePosition
}

var fragmentRegexp = regexp.MustCompile(`^line=(\d+)(?:,(\d+))?`)

func Parse(fragment string) (TextPlainFragmentIdentifier, int, error) {
	var result TextPlainFragmentIdentifier
	match := fragmentRegexp.FindStringSubmatch(fragment)
	if match == nil {
		return result, 0, errors.New("cannot parse fragment identifier")
	}
	line, err := strconv.ParseInt(match[1], 10, 64)
	if err != nil {
		return result, 0, fmt.Errorf("parsing fragment identifer: %w", err)
	}
	result.Start.Line = int(line)
	result.End.Line = int(line)
	if match[2] != "" {
		endLine, err := strconv.ParseInt(match[2], 10, 64)
		if err != nil {
			return result, 0, fmt.Errorf("parsing fragment identifier: %w", err)
		}
		result.End.Line = int(endLine)
	}
	return result, int(result.End.Line), nil
}
