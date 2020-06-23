languages = ["en", "fr", "de-1996", "it", "es", "fi", "is", "el-monoton", "ru", "zh-Hans", "ja", "kr"]
lengths = [50, 100, 150, 300]

Text.Streamer.matrix(languages, lengths)
|> Text.Streamer.save_as_csv