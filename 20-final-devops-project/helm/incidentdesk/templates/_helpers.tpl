{{- define "incidentdesk.fullname" -}}
{{- .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- end }}

{{- define "incidentdesk.labels" -}}
app.kubernetes.io/name: incidentdesk
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/* selector labels for one component: include with (dict "ctx" . "component" "backend") */}}
{{- define "incidentdesk.selector" -}}
app.kubernetes.io/name: incidentdesk
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{- define "incidentdesk.dbSecretName" -}}
{{- if .Values.postgres.existingSecret -}}
{{ .Values.postgres.existingSecret }}
{{- else -}}
{{ include "incidentdesk.fullname" . }}-db
{{- end -}}
{{- end }}

{{- define "incidentdesk.dbHost" -}}
{{ include "incidentdesk.fullname" . }}-postgres
{{- end }}

{{/* DB credentials for the backend: user/host/name from the ConfigMap, password from the Secret,
     then composed into DATABASE_URL with Kubernetes $(VAR) expansion. */}}
{{- define "incidentdesk.dbEnv" -}}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "incidentdesk.dbSecretName" . }}
      key: password
- name: DATABASE_URL
  value: "postgresql+psycopg://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):5432/$(DB_NAME)"
{{- end }}

{{- define "incidentdesk.containerSecurity" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: [ALL]
{{- end }}
