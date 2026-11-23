from ansible.errors import AnsibleError


def argon2(value, salt):
    try:
        from argon2.low_level import Type, hash_secret
    except Exception as e:
        raise AnsibleError("to use this filter, you need argon2_cffi pip package installed")

    digest = hash_secret(
        value.encode("utf-8"),
        salt.encode("utf-8"),
        time_cost=3,
        memory_cost=65536,
        parallelism=4,
        hash_len=32,
        type=Type.ID,
    )

    return digest.decode("ascii")


class FilterModule(object):
    def filters(self):
        return {
            "argon2": argon2,
        }
