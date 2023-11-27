# README

公文系統

### System 
```ruby 
ruby 3.1.2
rails 7.0.3
```

### Code Quality
```ruby 
# run before commit
rake dev_func:app_test
rake dev_func:check_style
rake dev_func:code_analysis

```

#### development
```
# .env
MYSQL_USER=
MYSQL_PASSWORD=

MSSQL_USER=
MSSQL_PASSWORD=
MSSQL_HOST=

# mail
SMTP_DOMAIN=""
SMTP_USER=""
SMTP_PASSWORD=""
```

#### production 
