import pytest

from app.calculator import add, calculate, divide, multiply, subtract


def test_add():
    assert add(10, 5) == 15


def test_subtract():
    assert subtract(10, 5) == 5


def test_multiply():
    assert multiply(10, 5) == 50


def test_divide():
    assert divide(10, 4) == 2.5


def test_divide_by_zero():
    with pytest.raises(ValueError, match="divide by zero"):
        divide(10, 0)


@pytest.mark.parametrize("op,expected", [("add", 7), ("subtract", 3), ("multiply", 10), ("divide", 2.5)])
def test_calculate_dispatch(op, expected):
    assert calculate(op, 5, 2) == expected


def test_calculate_unknown_op():
    with pytest.raises(ValueError, match="Unknown operation"):
        calculate("power", 2, 3)
