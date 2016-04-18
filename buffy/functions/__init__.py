#!/usr/bin/env python3

__FUNCS__ = {}


def get_function(func_name):
    return __FUNCS__[func_name.lower()]

# Import each function manually
# TODO: automate this part so function files are drop-in compatible
from .pong import FUNC_NAME, func  # noqa
__FUNCS__[FUNC_NAME.lower()] = (func, FUNC_NAME)

from .passthrough import FUNC_NAME, func  # noqa
__FUNCS__[FUNC_NAME.lower()] = (func, FUNC_NAME)

from .double import FUNC_NAME, func  # noqa
__FUNCS__[FUNC_NAME.lower()] = (func, FUNC_NAME)

from .marketspread import FUNC_NAME, func  # noqa
__FUNCS__[FUNC_NAME.lower()] = (func, FUNC_NAME)

from .fixrouter import FUNC_NAME, func  # noqa
__FUNCS__[FUNC_NAME.lower()] = (func, FUNC_NAME)

from .inputdoubler import FUNC_NAME, func  # noqa
__FUNCS__[FUNC_NAME.lower()] = (func, FUNC_NAME)

from .basic_wordcount import FUNC_NAME, func  # noqa
__FUNCS__[FUNC_NAME.lower()] = (func, FUNC_NAME)

from .wordcount_split import FUNC_NAME, func  # noqa
__FUNCS__[FUNC_NAME.lower()] = (func, FUNC_NAME)

from .wordcount_count import FUNC_NAME, func  # noqa
__FUNCS__[FUNC_NAME.lower()] = (func, FUNC_NAME)
