from typing import (
    List,
    Tuple,
)

from hummingbot.strategy.market_trading_pair_tuple import MarketTradingPairTuple
from hummingbot.strategy.vwap_trade import (
    VwapTradeStrategy
)
from hummingbot.strategy.vwap_trade.vwap_trade_config_map import vwap_trade_config_map


def start(self):
    try:
        total_order_amount = vwap_trade_config_map.get("total_order_amount").value
        total_order_per_session = vwap_trade_config_map.get("total_order_per_session").value
        order_type = vwap_trade_config_map.get("order_type").value
        is_buy = vwap_trade_config_map.get("is_buy").value
        time_delay = vwap_trade_config_map.get("time_delay").value
        is_vwap = vwap_trade_config_map.get("is_vwap").value
        num_individual_orders = vwap_trade_config_map.get("num_individual_orders").value
        messari_api_rate = vwap_trade_config_map.get("messari_api_rate").value
        percent_slippage = vwap_trade_config_map.get("percent_slippage").value
        use_messari_api = vwap_trade_config_map.get("use_messari_api").value
        order_percent_of_volume = vwap_trade_config_map.get("order_percent_of_volume").value
        market = vwap_trade_config_map.get("market").value.lower()
        raw_market_symbol = vwap_trade_config_map.get("market_trading_pair_tuple").value
        trading_time_duration = vwap_trade_config_map.get("trading_time_duration").value

        floor_price = None
        cancel_order_wait_time = None

        if order_type == "limit":
            floor_price = vwap_trade_config_map.get("floor_price").value
            cancel_order_wait_time = vwap_trade_config_map.get("cancel_order_wait_time").value
        buzzer_price = vwap_trade_config_map.get("buzzer_price").value
        buzzer_percent = vwap_trade_config_map.get("buzzer_percent").value
        num_trading_sessions = round(total_order_amount / total_order_per_session)

        if floor_price > buzzer_price:
            self._notify("invalid input: floor price cannot be greater than buzzer price")
            return
        if buzzer_percent > 200:
            self._notify("invalid input: buzzer percent cannot be greater than 200%")
            return
        if total_order_per_session > total_order_amount:
            self._notify("invalid input: total order per session cannot be greater than total order amount!")
            return
        if messari_api_rate < 60:
            self._notify("too frequent api call rate for Messari")
            return

        try:
            assets: Tuple[str, str] = self._initialize_market_assets(market, [raw_market_symbol])[0]
        except ValueError as e:
            self._notify(str(e))
            return

        market_names: List[Tuple[str, List[str]]] = [(market, [raw_market_symbol])]

        self._initialize_wallet(token_trading_pairs=list(set(assets)))
        self._initialize_markets(market_names)
        self.assets = set(assets)

        maker_data = [self.markets[market], raw_market_symbol] + list(assets)
        self.market_trading_pair_tuples = [MarketTradingPairTuple(*maker_data)]

        strategy_logging_options = VwapTradeStrategy.OPTION_LOG_ALL

        self.strategy = VwapTradeStrategy(market_infos=[MarketTradingPairTuple(*maker_data)],
                                          hb_app_notification=True,
                                          use_messari_api=use_messari_api,
                                          messari_api_rate=messari_api_rate,
                                          order_type=order_type,
                                          floor_price=floor_price,
                                          buzzer_price=buzzer_price,
                                          buzzer_percent=buzzer_percent,
                                          cancel_order_wait_time=cancel_order_wait_time,
                                          is_buy=is_buy,
                                          time_delay=time_delay,
                                          is_vwap=is_vwap,
                                          num_individual_orders=num_individual_orders,
                                          num_trading_sessions=num_trading_sessions,
                                          trading_time_duration=trading_time_duration,
                                          percent_slippage=percent_slippage,
                                          order_percent_of_volume=order_percent_of_volume,
                                          total_order_amount=total_order_amount,
                                          total_order_per_session=total_order_per_session,
                                          logging_options=strategy_logging_options)
    except Exception as e:
        self._notify(str(e))
        self.logger().error("Unknown error during initialization.", exc_info=True)
