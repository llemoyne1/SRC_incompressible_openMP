# 0337c — actually insert livevis env helper definitions

The 0337b guard checked for the token `env_int_0337`, but that token was already present at call sites. As a result the helper definitions were not inserted. This patch inserts the three helpers after `env_truthy_0260`.
