PRAGMA foreign_keys=ON;
PRAGMA journal_mode=WAL;

CREATE TABLE meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE schema_migrations (
  name TEXT PRIMARY KEY,
  sha256 TEXT NOT NULL,
  applied_utc TEXT NOT NULL
);

CREATE TABLE curations_applied (
  name TEXT PRIMARY KEY,
  sha256 TEXT NOT NULL,
  applied_utc TEXT NOT NULL
);

CREATE TABLE objects (
  object_id TEXT PRIMARY KEY,
  object_type TEXT NOT NULL CHECK(object_type IN ('MILESTONE','SYMBOL','ARTIFACT','GIT_COMMIT')),
  display_name TEXT NOT NULL,
  created_from TEXT,
  active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1))
);

CREATE TABLE milestones (
  object_id TEXT PRIMARY KEY REFERENCES objects(object_id) ON DELETE CASCADE,
  milestone_key TEXT NOT NULL UNIQUE,
  milestone_id TEXT NOT NULL,
  canonical_id TEXT,
  group_name TEXT,
  name TEXT NOT NULL,
  summary TEXT,
  nature TEXT,
  domain TEXT,
  status TEXT,
  confidence TEXT NOT NULL DEFAULT 'B',
  introduced_date TEXT,
  introduced_commit TEXT,
  tag TEXT,
  notes TEXT,
  source_file TEXT,
  source_row INTEGER
);
CREATE INDEX idx_milestones_id ON milestones(milestone_id);
CREATE INDEX idx_milestones_canonical ON milestones(canonical_id);

CREATE TABLE symbols (
  object_id TEXT PRIMARY KEY REFERENCES objects(object_id) ON DELETE CASCADE,
  namespace TEXT NOT NULL CHECK(namespace IN ('PARAM','ENV','CONTROL','OUTPUT','INTERNAL')),
  canonical_name TEXT NOT NULL,
  category TEXT,
  status TEXT,
  expected_type TEXT,
  default_value TEXT,
  constraints_text TEXT,
  effect_role TEXT,
  remarks TEXT,
  source_inventory TEXT,
  UNIQUE(namespace, canonical_name)
);
CREATE INDEX idx_symbols_name ON symbols(canonical_name);

CREATE TABLE symbol_names (
  id INTEGER PRIMARY KEY,
  symbol_object_id TEXT NOT NULL REFERENCES symbols(object_id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  name_kind TEXT NOT NULL,
  is_canonical INTEGER NOT NULL DEFAULT 0 CHECK(is_canonical IN (0,1)),
  source_file TEXT,
  source_row INTEGER,
  UNIQUE(symbol_object_id, name, name_kind)
);
CREATE INDEX idx_symbol_names_name ON symbol_names(name);

CREATE TABLE artifacts (
  object_id TEXT PRIMARY KEY REFERENCES objects(object_id) ON DELETE CASCADE,
  path TEXT NOT NULL UNIQUE,
  basename TEXT NOT NULL,
  kind TEXT NOT NULL,
  language TEXT,
  status TEXT,
  milestone_hint TEXT,
  description TEXT,
  sha256 TEXT
);
CREATE INDEX idx_artifacts_basename ON artifacts(basename);

CREATE TABLE relations (
  id INTEGER PRIMARY KEY,
  source_object_id TEXT NOT NULL REFERENCES objects(object_id) ON DELETE CASCADE,
  relation_type TEXT NOT NULL,
  target_object_id TEXT NOT NULL REFERENCES objects(object_id) ON DELETE CASCADE,
  confidence TEXT NOT NULL DEFAULT 'B',
  evidence_text TEXT,
  UNIQUE(source_object_id, relation_type, target_object_id)
);
CREATE INDEX idx_rel_source ON relations(source_object_id);
CREATE INDEX idx_rel_target ON relations(target_object_id);

CREATE TABLE evidence (
  id INTEGER PRIMARY KEY,
  object_id TEXT NOT NULL REFERENCES objects(object_id) ON DELETE CASCADE,
  evidence_type TEXT NOT NULL,
  path TEXT,
  commit_hash TEXT,
  tag TEXT,
  line_hint TEXT,
  source_inventory TEXT,
  confidence TEXT NOT NULL DEFAULT 'B',
  notes TEXT
);

CREATE TABLE git_commits (
  hash TEXT PRIMARY KEY,
  authored_date TEXT,
  committed_date TEXT,
  author_name TEXT,
  author_email TEXT,
  subject TEXT NOT NULL,
  parent_count INTEGER NOT NULL DEFAULT 0,
  is_merge INTEGER NOT NULL DEFAULT 0 CHECK(is_merge IN (0,1))
);
CREATE INDEX idx_git_commits_authored_date ON git_commits(authored_date);

CREATE TABLE git_tags (
  tag TEXT PRIMARY KEY,
  commit_hash TEXT REFERENCES git_commits(hash),
  tagged_date TEXT,
  tag_type TEXT NOT NULL DEFAULT 'LIGHTWEIGHT',
  tag_message TEXT
);
CREATE INDEX idx_git_tags_commit ON git_tags(commit_hash);

CREATE TABLE git_refs (
  ref_name TEXT PRIMARY KEY,
  ref_type TEXT NOT NULL CHECK(ref_type IN ('LOCAL_BRANCH','REMOTE_BRANCH','TAG')),
  commit_hash TEXT REFERENCES git_commits(hash),
  remote_name TEXT,
  is_symbolic INTEGER NOT NULL DEFAULT 0 CHECK(is_symbolic IN (0,1))
);
CREATE INDEX idx_git_refs_commit ON git_refs(commit_hash);

CREATE TABLE git_commit_refs (
  commit_hash TEXT NOT NULL REFERENCES git_commits(hash) ON DELETE CASCADE,
  ref_name TEXT NOT NULL REFERENCES git_refs(ref_name) ON DELETE CASCADE,
  PRIMARY KEY(commit_hash, ref_name)
);
CREATE INDEX idx_git_commit_refs_ref ON git_commit_refs(ref_name);

CREATE TABLE git_commit_files (
  commit_hash TEXT NOT NULL REFERENCES git_commits(hash) ON DELETE CASCADE,
  path TEXT NOT NULL,
  change_type TEXT NOT NULL,
  old_path TEXT NOT NULL DEFAULT '',
  PRIMARY KEY(commit_hash, path, old_path)
);
CREATE INDEX idx_git_commit_files_path ON git_commit_files(path);

CREATE TABLE git_commit_mainline_status (
  commit_hash TEXT PRIMARY KEY REFERENCES git_commits(hash) ON DELETE CASCADE,
  mainline_ref TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('IN_MAINLINE','PATCH_EQUIVALENT_IN_MAINLINE','UNIQUE_OUTSIDE_MAINLINE')),
  observed_branch TEXT,
  notes TEXT
);
CREATE INDEX idx_git_commit_mainline_status_status ON git_commit_mainline_status(status);

CREATE TABLE git_branch_audit (
  branch_name TEXT PRIMARY KEY,
  tip_commit TEXT REFERENCES git_commits(hash),
  mainline_ref TEXT NOT NULL,
  relation_to_mainline TEXT NOT NULL CHECK(relation_to_mainline IN ('MAINLINE','ANCESTOR_OF_MAINLINE','PATCH_EQUIVALENT_IN_MAINLINE','HAS_UNIQUE_PATCHES','AUDIT_ERROR')),
  unique_commits INTEGER NOT NULL DEFAULT 0,
  patch_unique_commits INTEGER NOT NULL DEFAULT 0,
  patch_equivalent_commits INTEGER NOT NULL DEFAULT 0,
  first_unique_date TEXT,
  last_unique_date TEXT,
  notes TEXT
);
CREATE INDEX idx_git_branch_audit_relation ON git_branch_audit(relation_to_mainline);

CREATE TABLE git_branch_commit_status (
  branch_name TEXT NOT NULL REFERENCES git_refs(ref_name) ON DELETE CASCADE,
  commit_hash TEXT NOT NULL REFERENCES git_commits(hash) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK(status IN ('PATCH_EQUIVALENT_IN_MAINLINE','UNIQUE_OUTSIDE_MAINLINE')),
  subject TEXT,
  PRIMARY KEY(branch_name, commit_hash)
);
CREATE INDEX idx_git_branch_commit_status_commit ON git_branch_commit_status(commit_hash);

CREATE TABLE git_milestone_candidates (
  candidate_id TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  normalized_label TEXT NOT NULL,
  candidate_family TEXT NOT NULL CHECK(candidate_family IN ('X','NUMERIC')),
  anchor_commit TEXT REFERENCES git_commits(hash),
  first_date TEXT,
  last_date TEXT,
  evidence_count INTEGER NOT NULL DEFAULT 0,
  max_confidence TEXT NOT NULL DEFAULT 'C' CHECK(max_confidence IN ('A','B','C')),
  status TEXT NOT NULL DEFAULT 'CANDIDATE' CHECK(status IN ('CANDIDATE','LINKED','CURATED','REJECTED')),
  linked_milestone_object_id TEXT REFERENCES milestones(object_id),
  notes TEXT
);
CREATE INDEX idx_git_candidates_label ON git_milestone_candidates(normalized_label);
CREATE INDEX idx_git_candidates_status ON git_milestone_candidates(status);

CREATE TABLE git_candidate_evidence (
  id INTEGER PRIMARY KEY,
  candidate_id TEXT NOT NULL REFERENCES git_milestone_candidates(candidate_id) ON DELETE CASCADE,
  evidence_type TEXT NOT NULL,
  commit_hash TEXT REFERENCES git_commits(hash),
  ref_name TEXT,
  path TEXT,
  evidence_text TEXT,
  confidence TEXT NOT NULL DEFAULT 'C' CHECK(confidence IN ('A','B','C'))
);
CREATE INDEX idx_git_candidate_evidence_candidate ON git_candidate_evidence(candidate_id);
CREATE INDEX idx_git_candidate_evidence_commit ON git_candidate_evidence(commit_hash);

CREATE TABLE raw_params_inventory (
  source_file TEXT NOT NULL,
  source_row INTEGER NOT NULL,
  name TEXT, entry_type TEXT, category TEXT, status TEXT, expected_type TEXT,
  default_value TEXT, values_constraints TEXT, canonical_field_target TEXT,
  aliases TEXT, effect_role TEXT, remarks TEXT, sources TEXT, source_inventory TEXT,
  PRIMARY KEY(source_file, source_row)
);

CREATE TABLE raw_env_inventory (
  source_file TEXT NOT NULL,
  source_row INTEGER NOT NULL,
  name TEXT, entry_type TEXT, category TEXT, status TEXT, expected_type TEXT,
  default_value TEXT, effect_role TEXT, remarks TEXT, sources TEXT, source_inventory TEXT,
  PRIMARY KEY(source_file, source_row)
);

CREATE TABLE raw_milestone_rows (
  source_file TEXT NOT NULL,
  source_row INTEGER NOT NULL,
  group_name TEXT, milestone_id TEXT, name TEXT, summary TEXT, status TEXT, raw_tex TEXT,
  PRIMARY KEY(source_file, source_row)
);

CREATE VIRTUAL TABLE search_fts USING fts5(
  object_id UNINDEXED,
  object_type UNINDEXED,
  title,
  body,
  tokenize='unicode61 remove_diacritics 2'
);
