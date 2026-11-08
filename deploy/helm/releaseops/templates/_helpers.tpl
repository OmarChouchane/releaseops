{{- define "releaseops.name" -}}
{{- .Release.Name | trunc 40 | trimSuffix "-" -}}
{{- end -}}

{{- define "releaseops.mysqlName" -}}
{{- printf "%s-mysql" (include "releaseops.name" .) -}}
{{- end -}}

{{- define "releaseops.labels" -}}
app.kubernetes.io/name: releaseops
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "releaseops.selectorLabels" -}}
app.kubernetes.io/name: releaseops
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: app
{{- end -}}

{{- define "releaseops.mysqlSelectorLabels" -}}
app.kubernetes.io/name: releaseops
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: mysql
{{- end -}}

{{/* An immutable digest wins; a tag is only accepted when no digest is set. */}}
{{- define "releaseops.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else if .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag -}}
{{- else -}}
{{- fail "set image.digest (preferred, immutable) or image.tag" -}}
{{- end -}}
{{- end -}}

{{- define "releaseops.secretName" -}}
{{- if .Values.secret.existingSecret -}}
{{- .Values.secret.existingSecret -}}
{{- else -}}
{{- printf "%s-db" (include "releaseops.name" .) -}}
{{- end -}}
{{- end -}}

{{- define "releaseops.dbHost" -}}
{{- default (include "releaseops.mysqlName" .) .Values.config.database.host -}}
{{- end -}}
