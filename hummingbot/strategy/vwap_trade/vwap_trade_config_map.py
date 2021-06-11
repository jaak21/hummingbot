from hummingbot.client.config.config_var import ConfigVar
from hummingbot.client.config.config_validators import (
    validate_exchange,
    validate_int,
    validate_bool,
    validate_decimal,
    validate_market_trading_pair,
)
from hummingbot.client.settings import (
    required_exchanges,
    EXAMPLE_PAIRS,
)
from typing import Optional


def symbol_prompt():
    market = vwap_trade_config_map.get("market").value
    example = EXAMPLE_PAIRS.get(market)
    return "Enter the token symbol you would like to trade on %s%s >>> " \
           % (market, f" (e.g. {example})" if example else "")


def str2bool(value: str):
    return str(value).lower() in ("yes", "true", "t", "1")


# checks if the symbol pair is valid
def validate_market_trading_pair_tuple(value: str) -> Optional[str]:
    market = vwap_trade_config_map.get("market").value
    return validate_market_trading_pair(market, value)


def order_percent_of_volume_prompt():
    percent_slippage = vwap_trade_config_map.get("percent_slippage").value
    default_value = 1
    return ("What percent of open order volume up to %s percent slippage do you want " % percent_slippage
            + "each order to be? (default is %s percent)? >>> " % default_value)


vwap_trade_config_map = {
    "strategy":
        ConfigVar(key="strategy",
                  prompt="",
                  default="vwap_trade"),
    "market":
        ConfigVar(key="market",
                  prompt="Enter the name of the exchange >>> ",
                  validator=validate_exchange,
                  on_validated=lambda value: required_exchanges.append(value),
                  prompt_on_new=True),
    "market_trading_pair_tuple":
        ConfigVar(key="market_trading_pair_tuple",
                  prompt=symbol_prompt,
                  validator=validate_market_trading_pair_tuple, prompt_on_new=True),
    "order_type":
        ConfigVar(key="order_type",
                  prompt="Enter type of order (limit/market) default is market >>> ",
                  type_str="str",
                  validator=lambda v: None if v in {"limit", "market", ""} else "Invalid order type.",
                  default="market", prompt_on_new=True),
    "total_order_amount":
        ConfigVar(key="total_order_amount",
                  prompt="What is your preferred quantity (denominated in the base asset, default is 1)? "
                         ">>> ",
                  default=1.0,
                  type_str="float", prompt_on_new=True),
    "total_order_per_session":
        ConfigVar(key="total_order_per_session",
                  prompt="What is the desired quantity per trading session (denominated in the base asset, default is 1)? "
                         ">>> ",
                  default=1.0,
                  validator=lambda v: validate_decimal(v, 0, vwap_trade_config_map.get("total_order_amount").value, inclusive=True),
                  type_str="float", prompt_on_new=True),
    "is_buy":
        ConfigVar(key="is_buy",
                  prompt="Enter True for Buy order and False for Sell order (default is Buy Order) >>> ",
                  type_str="bool",
                  default=True, validator=validate_bool, prompt_on_new=True),
    "is_vwap":
        ConfigVar(key="is_vwap",
                  prompt="Would you like to use VWAP or TWAP? (default is VWAP) >>> ",
                  type_str="bool",
                  default=True, validator=validate_bool, prompt_on_new=True),
    "num_individual_orders":
        ConfigVar(key="num_individual_orders",
                  prompt="Into how many individual orders do you want to split this order? (Enter 10 to indicate 10 individual orders. "
                         "Default is 1)? >>> ",
                  required_if=lambda: vwap_trade_config_map.get("is_vwap").value is False,
                  type_str="int",
                  default=1, prompt_on_new=True),
    "percent_slippage":
        ConfigVar(key="percent_slippage",
                  prompt="What percent of price do you want to calculate open order volume? (default is 0.1 percent slippage) >>> ",
                  required_if=lambda: vwap_trade_config_map.get("is_vwap").value is True,
                  type_str="float",
                  default=0.1, prompt_on_new=True),
    "order_percent_of_volume":
        ConfigVar(key="order_percent_of_volume",
                  prompt=order_percent_of_volume_prompt,
                  required_if=lambda: vwap_trade_config_map.get("is_vwap").value is True,
                  type_str="float",
                  default=0.01, prompt_on_new=True),
    "order_size_factor":
        ConfigVar(key="order_size_factor",
                  prompt="What constant factor do you want to divide the order sizes (if the order sizes are too high)? (default is 1) >>> ",
                  required_if=lambda: vwap_trade_config_map.get("is_vwap").value is True,
                  type_str="float",
                  validator=lambda v: validate_decimal(v, 1, inclusive=True),
                  default=1, prompt_on_new=True),
    "use_messari_api":
        ConfigVar(key="use_messari_api",
                  prompt="Enter True or False to use the Messari API for trading volume info (default is True) >>> ",
                  type_str="bool",
                  default=True,
                  validator=validate_bool, prompt_on_new=True),
    "messari_api_rate":
        ConfigVar(key="messari_api_rate",
                  prompt="How often to fetch trading volume from Messari ? (Enter 30 to indicate 30 seconds. "
                         "Default is 1)? >>> ",
                  required_if=lambda: vwap_trade_config_map.get("is_vwap").value is False,
                  type_str="int",
                  validator=lambda v: validate_int(v, min_value=30, inclusive=True),
                  default=30, prompt_on_new=True),
    "time_delay":
        ConfigVar(key="time_delay",
                  prompt="How many seconds do you want to wait between each individual order? (Enter 10 to indicate 10 seconds. "
                         "Default is 10)? >>> ",
                  type_str="float",
                  default=10, prompt_on_new=True),
    "floor_price":
        ConfigVar(key="floor_price",
                  prompt="What is the floor price of the limit order ? >>> ",
                  required_if=lambda: vwap_trade_config_map.get("order_type").value == "limit",
                  type_str="float", prompt_on_new=True),
    "cancel_order_wait_time":
        ConfigVar(key="cancel_order_wait_time",
                  prompt="How long do you want to wait before cancelling your limit order (in seconds). "
                         "(Default is 60 seconds) ? >>> ",
                  required_if=lambda: vwap_trade_config_map.get("order_type").value == "limit",
                  type_str="float",
                  default=60, prompt_on_new=True),
    "buzzer_price":
        ConfigVar(key="buzzer_price",
                  prompt="What is the ceiling price to accelerate the limit order sizes ? >>> ",
                  required_if=lambda: vwap_trade_config_map.get("order_type").value == "limit",
                  validator=lambda v: validate_decimal(v, vwap_trade_config_map.get("floor_price").value, inclusive=False),
                  type_str="float", prompt_on_new=True),
    "buzzer_percent":
        ConfigVar(key="buzzer_percent",
                  prompt="What is the desired percent increase if buzzer price is reached ? >>> ",
                  required_if=lambda: vwap_trade_config_map.get("order_type").value == "limit",
                  validator=lambda v: validate_decimal(v, 0, 200, inclusive=True),
                  type_str="float", prompt_on_new=True),
    "trading_time_duration":
        ConfigVar(key="trading_time_duration",
                  prompt="How many hours do you want to run the trade with the bot? "
                         "(Default is 24 hours)? >>> ",
                  type_str="float",
                  validator=lambda v: validate_decimal(v, 1, inclusive=False),
                  default=24, prompt_on_new=True),
    "pause_trading":
        ConfigVar(key="pause_trading",
                  prompt="Should pause the trading bot? >>> ",
                  type_str="bool",
                  default=False,
                  required_if=lambda: False,
                  validator=validate_bool),
}
