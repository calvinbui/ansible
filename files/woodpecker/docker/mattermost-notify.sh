#!/usr/bin/env bash

set -euo pipefail

PAYLOAD=$(cat <<-EOF
{
  "text": "🔴 Build failed: ${CI_REPO}",

  "username": "Woodpecker",
  "icon_url": "https://avatars.githubusercontent.com/u/84780935",

  "attachments": [
    {
      "color": "#FF0000",

      "title": "View Build",
      "title_link": "${CI_PIPELINE_URL}",

      "fields": [
        {
          "short": false,
          "title": "Commit",
          "value": "[$(echo "$CI_COMMIT_MESSAGE" | sed '/^\s*$/d' | head -n1)](${CI_PIPELINE_FORGE_URL})"
        },
        {
          "short": true,
          "title": "Branch",
          "value": "${CI_COMMIT_BRANCH}"
        },
        {
          "short": true,
          "title": "Event",
          "value": "${CI_PIPELINE_EVENT}"
        }
      ]
    }
  ]
}
EOF
)

curl -X POST "$MATTERMOST_WEBHOOK_URL" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD"
