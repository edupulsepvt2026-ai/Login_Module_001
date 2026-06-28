package model

// BranchWithAdminFlag is a branch row from management.management_table
// enriched with a flag indicating whether a tenant_admin user already exists.
type BranchWithAdminFlag struct {
	TenantID       string
	Name           string
	City           string
	State          string
	HasTenantAdmin bool
}

// TenantBranch holds the minimal branch info needed when validating
// that a branch belongs to the chain admin's chain.
type TenantBranch struct {
	TenantID   string
	ChainName  string
	BranchName string
}
