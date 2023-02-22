
# URLS

[1]: https://github.com/evaera/roblox-lua-promise


# IDEAS

- create standard hit functions (which can be added to)

- all the actors access the same functions rather
than having to call through a bindable function to other VMS

- simplify the proxy class and stuff, creating and minimizing BindableEvent calls;
eg: when projectile is destroyed, it calls the terminated function,
rather than doing it in the self:Destroy() and having to go through a BindableEvent

- if a projectile is not active,
remove it from the global resolver, otherwise re-add it
