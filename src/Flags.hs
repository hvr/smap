module Flags
  ( Hdl(Std, File)
  , Keyed(Keyed, UnKeyed)
  , Command(Cat, Sub)
  , Accuracy(Approximate, Exact)
  , command
  )
where

import qualified Data.Attoparsec.Text
                                     as A
import qualified Data.Text           as Text
import qualified Options.Applicative as O
import           Control.Applicative  ( many
                                      , (<|>)
                                      )
import           Crypto.MAC.SipHash   ( SipKey(..) )

data Hdl = Std | File FilePath

data Keyed = Keyed Hdl Hdl | UnKeyed Hdl

data Accuracy = Approximate SipKey | Exact

data Command = Cat Accuracy [Keyed] Hdl | Sub Accuracy Keyed [Keyed] Hdl

hdl :: A.Parser Hdl
hdl = stdin <|> path
 where
  stdin = Std <$ A.char '-'
  path  = File . Text.unpack <$> A.takeWhile (/= ',')

keyed :: A.Parser Keyed
keyed =
  (keyed <|> unkeyed)
    <*    (A.endOfInput A.<?> "more filepath characters than expected")
    A.<?> "Could not parse filepath"
 where
  unkeyed = UnKeyed <$> hdl
  keyed   = do
    _ <- A.char '+'
    k <- hdl
    _ <- A.char ','
    v <- hdl
    return (Keyed k v)

aToO :: A.Parser a -> O.ReadM a
aToO p = O.eitherReader (A.parseOnly p . Text.pack)

accuracy :: O.Parser Accuracy
accuracy = approx <|> exact
 where
  approx = O.flag'
    (Approximate (SipKey 0 0))
    (O.short 'a' <> O.long "approximate" <> O.help
      "For deduplication, store a 64-bit siphash rather than the whole line. Can save memory"
    )
  exact = pure Exact


catCommand :: O.Mod O.CommandFields Command
catCommand = O.command "cat" $ O.info (value O.<**> O.helper) O.fullDesc
 where
  value = Cat <$> accuracy <*> many in_ <*> out
  in_   = O.argument
    (aToO keyed)
    (  O.metavar "INFILE"
    <> O.help
         "Can specify 0 or more files. Use '-' for stdin. Use +keyfile,valfile for separate keys and values. Uses stdin if none specified."
    )
  out = O.option
    (aToO hdl)
    (O.metavar "OUTFILE" <> O.short 'o' <> O.long "out" <> O.value Std <> O.help
      "Defaults to stdout."
    )

subCommand :: O.Mod O.CommandFields Command
subCommand = O.command "sub" $ O.info (value O.<**> O.helper) O.fullDesc
 where
  value = Sub <$> accuracy <*> plus <*> many minus <*> out
  plus  = O.argument
    (aToO keyed)
    (  O.metavar "PLUSFILE"
    <> O.help
         "Can specify 0 or more files. Use '-' for stdin. Use +keyfile,valfile for separate keys and values."
    )
  minus = O.argument
    (aToO keyed)
    (O.metavar "MINUSFILE" <> O.help "Can specify 0 or more files. Use '-' for stdin.")
  out = O.option
    (aToO hdl)
    (O.metavar "OUTFILE" <> O.short 'o' <> O.long "out" <> O.value Std <> O.help
      "Defaults to stdout."
    )

command :: IO Command
command =
  O.execParser (O.info ((O.subparser (catCommand <> subCommand)) O.<**> O.helper) O.fullDesc)
