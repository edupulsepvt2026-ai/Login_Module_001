package model

// MasterOption is a generic {id, name} lookup row — genders, qualifications,
// subjects, languages all shape the same way.
type MasterOption struct {
	ID   string
	Name string
}

// ClassOption is a class paired with its available sections.
type ClassOption struct {
	ID       string
	Name     string
	Sections []MasterOption
}

// ClassSectionPair is one (class_id, section_id) assignment for a teacher.
type ClassSectionPair struct {
	ClassID   string `json:"class_id"`
	SectionID string `json:"section_id"`
}
