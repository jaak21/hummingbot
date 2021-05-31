from hummingbot.script.script_base import ScriptBase
from decimal import Decimal
from hummingbot.core.event.events import (
    BuyOrderCompletedEvent,
    SellOrderCompletedEvent
)

from os.path import realpath, join

s_decimal_1 = Decimal("1")
LOGS_PATH = realpath(join(__file__, "../../logs/"))
SCRIPT_LOG_FILE = f"{LOGS_PATH}/logs_yt_monitor_script.log"


def print_comma_only(number):
    return "{:,.2f}".format(number)


def print_currency(amount):
    if amount <= 1:
        return "${:,.6f}".format(amount)
    else:
        return "${:,.2f}".format(amount)


class YTMonitorScript(ScriptBase):
    """
    Demonstrates a monitoring script that can take external inputs from a stream and execute a number of scripts based on the input.
    This is experimental and assumes that the input stream is authenticated.
    """
    # 1. measure volatility -> if too high, then send a stop signal
    # 2. track profit target? -> if mid price is too low high
    # 3. track how much fees paid? -> if too high, then allow sending a signal back
    def __init__(self):
        super().__init__()
        self.url = None
        self.status = "No action"
        self._has_updated = False
        self.total_units_bought = 0
        self.total_units_sold = 0
        self.total_balance = 0
        self.average_price = 0
        self._first_time_only = True

    def on_tick(self):
        strategy = self.pmm_parameters
        assert strategy is not None
        # market_info = self.pmm_market_info
        if self._first_time_only:
            self._first_time_only = False

    def update_balances(self, units, price, is_buy):
        self.total_balance += round(price, 2)
        if is_buy:
            self.total_units_bought += units
            self.average_price = round(float(self.total_balance / self.total_units_bought), 2)
        else:
            self.total_units_sold += units
            self.average_price = round(float(self.total_balance / self.total_units_sold), 2)
        return

    def on_buy_order_completed(self, event: BuyOrderCompletedEvent):
        token = event.base_asset
        price = event.quote_asset_amount
        units = event.base_asset_amount
        # print(f"Bought {token}: {amount} units @ ${price} {price_currency}")
        self.update_balances(units, price, True)
        self.status = f"bought = {print_comma_only(self.total_units_bought)} {token}, "
        self.status += f"total balance = {print_currency(self.total_balance)}, "
        self.status += f"avg price = {print_currency(self.average_price)}"
        self.log(self.status)

    def on_sell_order_completed(self, event: SellOrderCompletedEvent):
        token = event.base_asset
        price = event.quote_asset_amount
        units = event.base_asset_amount
        # print(f"Sold {token}: {amount} units @ ${price} {price_currency}")
        self.update_balances(units, price, False)
        self.status = f"sold = {print_comma_only(self.total_units_sold)} {token}, "
        self.status += f"total balance = {print_currency(self.total_balance)}, "
        self.status += f"avg price = {print_currency(self.average_price)}"
        self.log(self.status)

    def on_status(self):
        return f"{self.status}"
