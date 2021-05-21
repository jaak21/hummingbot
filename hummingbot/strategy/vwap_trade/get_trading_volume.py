from messari import Messari
from datetime import date
import json


def get_trading_volume(crypto_exchange, token_pair, start_date, end_date, duration, api_key=None):
    messari = Messari(key=api_key)
    market_key = crypto_exchange + "-" + token_pair.lower()
    query_params = {
        'start': start_date,
        'end': end_date,
        'interval': duration,
        'columns': 'volume',
        'order': 'ascending',
        'format': 'json',
        'timestamp-format': 'rfc3339'
    }

    resp = messari.get_market_timeseries(market_key=market_key, metric_id='price', **query_params)

    print(json.dumps(resp, indent=4))


def get_asset_info(token):
    messari = Messari()
    fields = 'symbol,name,slug'
    resp = messari.get_asset(asset_key=token, fields=fields)
    print(json.dumps(resp, indent=4))


def get_asset_profile(token):
    messari = Messari()
    fields = 'symbol,name,profile/general/overview/project_details'
    resp = messari.get_asset_profile(asset_key=token, fields=fields)
    print(json.dumps(resp, indent=4))


def get_asset_metrics(token):
    messari = Messari()
    fields = 'id,slug,symbol,market_data/price_usd,market_data/volume_last_24_hours'
    resp = messari.get_asset_metrics(asset_key=token, fields=fields)
    print(json.dumps(resp, indent=4))


DEFAULT_CURRENCY = "USD"


class TokenMetrics:
    def __init__(self, token, exchange=None, api_key=None, verbose=False):
        self.token = token.lower()
        self.exchange = exchange
        self.messari = Messari(key=api_key)
        self._data = {"24hr_trading_volume": None, "1hr_trading_volume": None, "price": None}
        self._token_pair = token + "-" + DEFAULT_CURRENCY
        self._verbose = verbose

    def _fetch_trading_volume(self):
        fields = 'symbol,market_data/price_usd,market_data/volume_last_24_hours'
        resp = self.messari.get_asset_metrics(asset_key=self.token, fields=fields)
        if resp.get("data") is None:
            if self._verbose:
                print("Failed to get data")
            return None
        data = resp.get("data")
        if self._verbose:
            print(json.dumps(data, indent=4))
        if data.get("market_data"):
            self._data["price"] = data["market_data"]["price_usd"]
            self._data["24hr_trading_volume"] = data["market_data"].get("volume_last_24_hours")
            return self._data["24hr_trading_volume"]
        return None

    def _fetch_market_data(self):
        fields = 'symbol,market_data/price_usd,market_data/ohlcv_last_1_hour/volume'
        resp = self.messari.get_asset_metrics(asset_key=self.token, fields=fields)
        if resp.get("data") is None:
            if self._verbose:
                print("Failed to get data")
            return None
        data = resp.get("data")
        if self._verbose:
            print(json.dumps(data, indent=4))
        if data.get("market_data"):
            self._data["1hr_trading_volume"] = data["market_data"]["ohlcv_last_1_hour"]["volume"]
            return self._data["1hr_trading_volume"]
        return None

    def get_24hr_trading_volume(self):
        self._fetch_trading_volume()
        return self._data["24hr_trading_volume"]

    def get_price(self):
        self._fetch_trading_volume()
        return self._data["price"]

    def get_1hr_trading_volume_on_exchange(self):
        if self.exchange is None:
            return 0
        market_key = self.exchange + "-" + self._token_pair.lower()
        today = date.today()

        start_date = today.strftime("%Y-%m-%d")
        end_date = start_date
        duration = '1h'

        query_params = {
            'start': start_date,
            'end': end_date,
            'interval': duration,
            'columns': 'volume',
            'order': 'ascending',
            'format': 'json',
            'timestamp-format': 'rfc3339'
        }
        resp = self.messari.get_market_timeseries(market_key=market_key, metric_id='price', **query_params)
        if self._verbose:
            print(json.dumps(resp, indent=4))
        if resp.get("data") is None:
            print("Failed to get data")
            return None
        data = resp.get("data")
        values = data.get("values")[0]
        self._data["1hr_trading_volume_time"], self._data["1hr_trading_volume"] = values[0], values[1]
        return self._data["1hr_trading_volume"]

    def get_1hr_trading_volume(self):
        self._fetch_market_data()
        return self._data["1hr_trading_volume"]

    def get_market_info(self):
        # fields='id,slug,symbol,metrics/market_data/price_usd'
        fields = 'exchange_name,pair,last_trade_at'
        resp = self.messari.get_all_markets(fields=fields)
        print(json.dumps(resp, indent=4))

    def get_all_assets(self):
        # Lists all of the available timeseries metric IDs for assets.
        # Use query parameters
        query = {
            'with-profiles': False,
            'with-metrics': False,
            'fields': 'id,slug,symbol,metrics/market_data/price_usd'
        }
        resp = self.messari.get_all_assets(**query)
        print(json.dumps(resp, indent=4))


if __name__ == "__main__":
    duration = '1h'
    crypto_exchange = 'coinbase'
    token_pair = 'xtz-usd'

    tm = TokenMetrics('XTZ', exchange='coinbase', verbose=True)
    print("Using get_market_timeseries() api ...")
    print("Trading volume (1 hr):", tm.get_1hr_trading_volume_on_exchange())
    print("Current price: ", tm.get_price())
