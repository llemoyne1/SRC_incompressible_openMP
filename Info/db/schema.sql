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
  subject TEXT NOT NULL
);
CREATE TABLE git_tags (
  tag TEXT PRIMARY KEY,
  commit_hash TEXT REFERENCES git_commits(hash),
  tagged_date TEXT
);

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
