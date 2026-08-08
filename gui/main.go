package main

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"

	_ "modernc.org/sqlite"
)

const dbPath = `C:\Windows\Temp\clipix.db`
const pollInterval = 500 * time.Millisecond
const numSlots = 9
const previewLen = 20

type slotItem struct {
	kind  string
	value string
}

func summarize(slot int, items []slotItem) string {
	if len(items) == 0 {
		return fmt.Sprintf("Slot %d: (empty)", slot)
	}
	preview := items[0].value
	runes := []rune(preview)
	if len(runes) > previewLen {
		preview = string(runes[:previewLen])
	}
	preview = strings.ReplaceAll(preview, "\n", " ")

	var suffix string
	if items[0].kind == "text" {
		suffix = "(text)"
	} else {
		suffix = fmt.Sprintf("(%d item(s))", len(items))
	}
	return fmt.Sprintf("Slot %d: %s...%s", slot, preview, suffix)
}

func fetchSlots(db *sql.DB) (map[int][]slotItem, error) {
	rows, err := db.Query(`SELECT slot, kind, value FROM slot_items ORDER BY slot, position;`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make(map[int][]slotItem)
	for rows.Next() {
		var slot int
		var kind, value string
		if err := rows.Scan(&slot, &kind, &value); err != nil {
			continue
		}
		result[slot] = append(result[slot], slotItem{kind: kind, value: value})
	}
	return result, rows.Err()
}

func main() {
	a := app.New()
	w := a.NewWindow("ClipIX")

	labels := make([]*widget.Label, numSlots)
	items := make([]fyne.CanvasObject, numSlots)
	for i := 0; i < numSlots; i++ {
		labels[i] = widget.NewLabel(fmt.Sprintf("Slot %d: (empty)", i+1))
		items[i] = labels[i]
	}
	w.SetContent(container.NewVBox(items...))
	w.Resize(fyne.NewSize(360, 260))

	go func() {
		var db *sql.DB
		missCount := 0

		for {
			time.Sleep(pollInterval)

			if db == nil {
				conn, err := sql.Open("sqlite", dbPath+"?mode=ro")
				if err != nil {
					continue
				}
				db = conn
			}

			slotsData, err := fetchSlots(db)
			if err != nil {
				missCount++
				if missCount >= 4 {
					db.Close()
					a.Quit()
					return
				}
				continue
			}
			missCount = 0

			for i := 0; i < numSlots; i++ {
				slotNum := i + 1
				text := summarize(slotNum, slotsData[slotNum])
				label := labels[i]
				fyne.Do(func() {
					label.SetText(text)
				})
			}
		}
	}()

	w.ShowAndRun()
}