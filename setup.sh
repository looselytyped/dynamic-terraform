#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  echo "Loading Aliases"
  alias v="vagrant" \
    && alias d="docker compose down -v" \
      && alias u="docker compose up" \
      && alias up="docker compose up --build" \
    && alias t=terraform \
      && alias tp='terraform plan' \
      && alias tc='terraform console' \
      && alias ta='terraform apply -auto-approve' \
      && alias td='terraform destroy' \
      && alias tda='terraform destroy -auto-approve' \
  && code .
else
  echo "You need to source this script ... Please try 'source setup.sh'."
fi

