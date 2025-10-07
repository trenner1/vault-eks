# CloudWatch Insights Queries for Vault Audit Logs

This document contains useful CloudWatch Insights queries for analyzing Vault audit logs.

## Basic Queries

### 1. View All Audit Events (Last Hour)
```sql
fields @timestamp, type, request.operation, request.path, auth.display_name
| sort @timestamp desc
| limit 100
```

### 2. Failed Authentication Attempts
```sql
fields @timestamp, request.path, request.remote_address, error
| filter type = "response" and ispresent(error)
| sort @timestamp desc
```

### 3. Permission Denied Events
```sql
fields @timestamp, request.path, auth.display_name, auth.policies, request.operation
| filter auth.policy_results.allowed = false or error like /permission denied/
| sort @timestamp desc
```

## Authentication Analysis

### 4. Successful Logins by Role
```sql
fields @timestamp, auth.display_name, auth.metadata.role, request.remote_address
| filter request.path like /auth\/jenkins-jwt\/login/ and type = "response"
| stats count() by auth.metadata.role
```

### 5. Token Creation Events
```sql
fields @timestamp, auth.display_name, request.path, response.auth.policies
| filter request.path like /auth\/token\/create/
| sort @timestamp desc
| limit 50
```

### 6. Failed Login Attempts
```sql
fields @timestamp, request.path, request.remote_address, request.data.role, error
| filter request.path like /login/ and ispresent(error)
| sort @timestamp desc
```

## Secret Access Patterns

### 7. All Secret Read Operations
```sql
fields @timestamp, request.path, auth.display_name, auth.metadata.role
| filter request.operation = "read" and request.path like /kv\/data/
| sort @timestamp desc
| limit 100
```

### 8. Secret Access by Path
```sql
fields @timestamp, auth.display_name, auth.metadata.role, request.path
| filter request.path like /kv\/data/
| stats count() by request.path, auth.metadata.role
| sort count() desc
```

### 9. Secrets Accessed by User/Role
```sql
fields @timestamp, request.path, auth.display_name, auth.metadata.role
| filter request.path like /kv\/data/
| stats count() by auth.display_name, auth.metadata.role
| sort count() desc
```

### 10. Cross-Team Access Attempts (Failed)
```sql
fields @timestamp, request.path, auth.display_name, auth.metadata.role, auth.policies
| filter auth.policy_results.allowed = false and request.path like /kv\/data/
| sort @timestamp desc
```

## Security Monitoring

### 11. High-Privilege Operations
```sql
fields @timestamp, request.path, request.operation, auth.display_name
| filter request.path like /sys\// and request.operation in ["create", "update", "delete"]
| sort @timestamp desc
```

### 12. Token Revocations
```sql
fields @timestamp, auth.display_name, request.path, auth.metadata
| filter request.path like /revoke/
| sort @timestamp desc
```

### 13. Activity by IP Address
```sql
fields @timestamp, request.remote_address, request.path, auth.display_name
| stats count() by request.remote_address
| sort count() desc
```

### 14. Unusual Activity (High Volume)
```sql
fields @timestamp, auth.display_name, request.operation
| stats count() as activity_count by auth.display_name, bin(5m)
| filter activity_count > 50
| sort @timestamp desc
```

## Token Management

### 15. Token Lifecycle (Create to Revoke)
```sql
fields @timestamp, request.path, auth.accessor, auth.display_name
| filter request.path like /auth\/token\/create/ or request.path like /revoke/
| sort @timestamp desc
```

### 16. Tokens by TTL
```sql
fields @timestamp, auth.display_name, response.auth.token_ttl, request.path
| filter request.path like /auth\/token\/create/
| stats avg(response.auth.token_ttl), max(response.auth.token_ttl), min(response.auth.token_ttl)
```

### 17. Token Usage Tracking
```sql
fields @timestamp, auth.display_name, auth.remaining_uses, request.path
| filter ispresent(auth.remaining_uses)
| filter auth.remaining_uses < 5
| sort @timestamp desc
```

## Performance & Debugging

### 18. Slow Operations (If timing is logged)
```sql
fields @timestamp, request.path, request.operation
| sort @timestamp desc
| limit 100
```

### 19. Request Volume by Hour
```sql
fields @timestamp, request.operation, type
| filter type = "request"
| stats count() as requests by bin(1h)
| sort bin(1h) desc
```

### 20. Most Accessed Paths
```sql
fields request.path
| stats count() as access_count by request.path
| sort access_count desc
| limit 20
```

## Entity & Identity Analysis

### 21. New Entity Creations
```sql
fields @timestamp, auth.entity_id, auth.display_name, auth.entity_created
| filter auth.entity_created = true
| sort @timestamp desc
```

### 22. Activity by Team/Role
```sql
fields @timestamp, auth.metadata.role, auth.metadata.job, request.path
| filter ispresent(auth.metadata.role)
| stats count() by auth.metadata.role, auth.metadata.job
| sort count() desc
```

### 23. User Activity Summary
```sql
fields auth.metadata.user_id, auth.metadata.role, request.operation
| filter ispresent(auth.metadata.user_id)
| stats count() by auth.metadata.user_id, auth.metadata.role, request.operation
```

## Policy Analysis

### 24. Policy Evaluation Results
```sql
fields @timestamp, auth.display_name, auth.policy_results.allowed, request.path, auth.policies
| filter ispresent(auth.policy_results)
| stats count() by auth.policy_results.allowed, auth.policies
```

### 25. Policies Granting Access
```sql
fields @timestamp, request.path, auth.policy_results.granting_policies
| filter auth.policy_results.allowed = true
| filter ispresent(auth.policy_results.granting_policies)
| sort @timestamp desc
```

## Compliance & Audit

### 26. All Write Operations
```sql
fields @timestamp, auth.display_name, request.path, request.operation, request.data
| filter request.operation in ["create", "update", "delete"]
| sort @timestamp desc
```

### 27. Sensitive Path Access
```sql
fields @timestamp, auth.display_name, request.path, request.remote_address
| filter request.path like /prod/ or request.path like /sys\//
| sort @timestamp desc
```

### 28. Audit Trail for Specific Secret
```sql
fields @timestamp, auth.display_name, request.operation, request.remote_address
| filter request.path = "kv/data/dev/apps/mobile-app/example"
| sort @timestamp desc
```

## Real-Time Alerts (Use as Metric Filters)

### 29. Failed Auth Rate
```sql
fields @timestamp
| filter type = "response" and ispresent(error) and request.path like /login/
| stats count() as failed_auth by bin(5m)
| filter failed_auth > 10
```

### 30. Root Token Usage
```sql
fields @timestamp, auth.display_name, request.path, request.remote_address
| filter auth.display_name = "root" or auth.accessor like /root/
| sort @timestamp desc
```

## Usage Tips

1. **Time Range**: Adjust the time range in CloudWatch console (top right) to narrow results
2. **Visualization**: Click "Visualization" tab to see graphs of aggregated data
3. **Export**: Use "Actions" → "Export results to CSV" for reporting
4. **Alerts**: Create CloudWatch alarms from metric filters for security events
5. **Field Extraction**: CloudWatch auto-parses JSON - just reference fields with dot notation

## Running Queries via CLI

```bash
# Replace with your log group name and region
LOG_GROUP="/aws/eks/vault/audit"
REGION="us-west-2"

# Example: Get failed logins from last hour
aws logs start-query \
  --log-group-name $LOG_GROUP \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, request.path, error | filter ispresent(error)' \
  --region $REGION
```

## Creating Metric Filters

For real-time alerting, create metric filters:

```bash
# Example: Alert on permission denied events
aws logs put-metric-filter \
  --log-group-name $LOG_GROUP \
  --filter-name "vault-permission-denied" \
  --filter-pattern '{ $.auth.policy_results.allowed = false }' \
  --metric-transformations \
    metricName=VaultPermissionDenied,metricNamespace=Vault/Audit,metricValue=1 \
  --region $REGION
```

Then create an alarm on that metric in CloudWatch.
