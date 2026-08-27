# Bug: System Permissions form 404s — every user, every install

**Version:** 2.31.1 (self-hosted)
**Impact:** System-level permissions cannot be granted or revoked through the UI at all.

## Reproduce

1. Users → pick any user → **System Permissions**.
2. Change anything, submit.
3. `404 Not Found`. Server log:

```
Started PATCH "/c/thomas@example.com/users/2/system_permissions"
ActionController::RoutingError (No route matches [PATCH] "/c/thomas@example.com/users/2/system_permissions")
```

The edit page itself loads correctly, at `/c/newsletter/users/thomas@example.com/system_permissions/edit`.

## Cause

`app/views/user_system_permissions/edit.html.erb:15` passes two positional arguments
to a **singular**-resource helper:

```erb
form_url: user_user_system_permission_path(@user, @user_system_permission),
```

The route has exactly two dynamic segments:

```
PATCH  /c/:channel_slug/users/:user_email/system_permissions(.:format)   {user_email: /[^\/]+/}
```

`resource :user_system_permission` contributes no member segment, so the second
argument does not go where it looks like it goes. Rails fills the segments
positionally:

| segment | gets | value |
| --- | --- | --- |
| `:channel_slug` | `@user` | `thomas@example.com` |
| `:user_email` | `@user_system_permission` | `2` |

Result: `/c/thomas@example.com/users/2/system_permissions`. `:channel_slug` carries no
constraint, so the default segment pattern rejects the dots in the email and nothing
matches — a routing 404 rather than a controller-level one.

## Fix

Drop the second argument:

```erb
form_url: user_user_system_permission_path(@user),
```

With one argument, `handle_positional_args` binds it to `:user_email` and
`:channel_slug` comes from `default_url_options` — which is why the sibling call on
the same page already works:

```ruby
# app/controllers/user_system_permissions_controller.rb:12
add_breadcrumb 'System Permissions', edit_user_user_system_permission_path(@user)
```

No other call site passes the extra argument (`app/views/users/show.html.erb:68,134`
both pass one).

## Note

A regression test would need the `/c/:channel_slug` prefix to be exercised — the bug
is invisible without it, since the surplus argument only misbinds because the scope
adds a second dynamic segment ahead of `:user_email`.
