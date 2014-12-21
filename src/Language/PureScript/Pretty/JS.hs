-----------------------------------------------------------------------------
--
-- Module      :  Language.PureScript.Pretty.JS
-- Copyright   :  (c) Phil Freeman 2013
-- License     :  MIT
--
-- Maintainer  :  Phil Freeman <paf31@cantab.net>
-- Stability   :  experimental
-- Portability :
--
-- |
-- Pretty printer for the Javascript AST
--
-----------------------------------------------------------------------------

module Language.PureScript.Pretty.JS (
    prettyPrintJS
) where

import Language.PureScript.Pretty.Common
import Language.PureScript.CodeGen.JS (identNeedsEscaping, unqual, anyType)
import Language.PureScript.CodeGen.JS.AST

import Data.List
import Data.Char (isSpace)
import Data.Maybe (fromMaybe)
import qualified Control.Arrow as A
import Control.Arrow ((<+>))
import Control.PatternArrows
import Control.Applicative
import Control.Monad.State
import Numeric

import Debug.Trace ()

literals :: Pattern PrinterState JS String
literals = mkPattern' match
  where
  match :: JS -> StateT PrinterState Maybe String
  match (JSNumericLiteral n) = return $ either show show n
  match (JSStringLiteral s) = return $ string s
  match (JSBooleanLiteral True) = return "true"
  match (JSBooleanLiteral False) = return "false"
  match (JSArrayLiteral []) = fmap concat $ sequence
    [ return $ "[]" ++ anyType ++ "{}"
    , return ""
    ]
  match (JSArrayLiteral xs) = fmap concat $ sequence
    [ return "[ "
    , fmap (intercalate ", ") $ forM xs prettyPrintJS'
    , return " ]"
    ]
  match (JSObjectLiteral []) = return "nil"
  match (JSObjectLiteral ps) = fmap concat $ sequence
    [ return "{\n"
    , withIndent $ do
        jss <- forM ps $ \(key, value) -> fmap ((objectPropertyToString key ++ ": ") ++) . prettyPrintJS' $ value
        indentString <- currentIndent
        return $ intercalate ", \n" $ map (indentString ++) jss
    , return "\n"
    , currentIndent
    , return "}"
    ]
    where
    objectPropertyToString :: String -> String
    objectPropertyToString s | identNeedsEscaping s = show s
                             | otherwise = s
  match (JSBlock sts) = fmap concat $ sequence
    [ return "{\n"
    , withIndent $ prettyStatements sts
    , return "\n"
    , currentIndent
    , return "}"
    ]
  match (JSVar ident) = return ident
  match (JSVariableIntroduction ident value) = fmap concat $ sequence $
    if ident == "Main.Main" then [return "func main() {",
                                  return "\n",
                                  maybe (return "") (fmap ("  " ++) . prettyPrintJS') value,
                                  return "\n",
                                  return $ "}"]
    else case value of
      (Just (JSFunction Nothing [arg] ret)) ->
          if '.' `elem` ident then [return "func ",
                                    return (unqual ident),
                                    return (parens arg),
                                    return " ",
                                    return anyType, -- TODO: look for JSReturn and set accordingly?
                                    return " ",
                                    prettyPrintJS' ret]
                              else [return "var ",
                                    return ident,
                                    return " func ",
                                    return (parens anyType),
                                    return " ",
                                    return anyType, -- TODO: look for JSReturn and set accordingly?
                                    return "; ", -- TODO: line break and align
                                    return ident,
                                    maybe (return "") (fmap (" = " ++) . prettyPrintJS') value]
      (Just (JSInit a b)) ->
           [return "var ",
            return (unqual ident),
            return " ",
            prettyPrintJS' a,
            return "\n",
            return "func init() { ",
            return "\n",
            return (unqual ident),
            return " = ",
            maybe (return "") prettyPrintJS' value,
            return "\n",
            return "}",
            return "\n"]

      (Just (JSObjectLiteral [])) ->
           [return "var ",
            return (unqual ident),
            return " ",
            return "struct{}"]

      _ -> [return "var ",
            return (unqual ident),
            maybe (return "") (fmap (" = " ++) . prettyPrintJS') value]

  match (JSAssignment target value) = fmap concat $ sequence
    [ prettyPrintJS' target
    , return " = "
    , prettyPrintJS' value
    ]
  match (JSWhile cond sts) = fmap concat $ sequence
    [ return "for "
    , do c <- prettyPrintJS' cond
         return (if c == "true" then "" else c)
    , return " "
    , prettyPrintJS' sts
    ]
  match (JSFor ident start end sts) = fmap concat $ sequence
    [ return $ "for " ++ ident ++ " := "
    , prettyPrintJS' start
    , return $ "; " ++ ident ++ " < "
    , prettyPrintJS' end
    , return $ "; " ++ ident ++ "++ "
    , prettyPrintJS' sts
    ]
  match (JSForIn ident obj sts) = fmap concat $ sequence
    [ return $ "for (" ++ ident ++ " in "
    , prettyPrintJS' obj
    , return " "
    , prettyPrintJS' sts
    ]
  match (JSIfElse cond thens elses) = fmap concat $ sequence
    [ return "if "
    , prettyPrintJS' cond
    , return " "
    , prettyPrintJS' thens
    , maybe (return "") (fmap (" else " ++) . prettyPrintJS') elses
    ]
  match (JSReturn value) = fmap concat $ sequence
    [ return "return "
    , prettyPrintJS' value
    ]
  match (JSThrow value) = fmap concat $ sequence
    [ return "panic ("
    , prettyPrintJS' value
    , return ")"
    ]
  match (JSBreak lbl) = return $ "break " ++ lbl
  match (JSContinue lbl) = return $ "goto " ++ lbl
  match (JSLabel lbl js) = fmap concat $ sequence
    [ return $ lbl ++ ": "
    , prettyPrintJS' js
    ]
  match (JSRaw js) = return js
  match _ = mzero

string :: String -> String
string s = '"' : concatMap encodeChar s ++ "\""
  where
  encodeChar :: Char -> String
  encodeChar '\b' = "\\b"
  encodeChar '\t' = "\\t"
  encodeChar '\n' = "\\n"
  encodeChar '\v' = "\\v"
  encodeChar '\f' = "\\f"
  encodeChar '\r' = "\\r"
  encodeChar '"'  = "\\\""
  encodeChar '\\' = "\\\\"
  encodeChar c | fromEnum c > 0xFFF = "\\u" ++ showHex (fromEnum c) ""
  encodeChar c | fromEnum c > 0xFF = "\\u0" ++ showHex (fromEnum c) ""
  encodeChar c = [c]

conditional :: Pattern PrinterState JS ((JS, JS), JS)
conditional = mkPattern match
  where
  match (JSConditional cond th el) = Just ((th, el), cond)
  match _ = Nothing

accessor :: Pattern PrinterState JS (String, JS)
accessor = mkPattern match
  where
  match (JSAccessor prop val) = Just (prop, val)
  match _ = Nothing

indexer :: Pattern PrinterState JS (String, JS)
indexer = mkPattern' match
  where
  match (JSIndexer index val) = (,) <$> prettyPrintJS' index <*> pure val
  match _ = mzero

lam :: Pattern PrinterState JS ((Maybe String, [String]), JS)
lam = mkPattern match
  where
  match (JSFunction name args ret) = Just ((name, args), ret)
  match _ = Nothing

dat' :: Pattern PrinterState JS (String, JS)
dat' = mkPattern match
  where
  match (JSData' name fields) = Just (name, fields)
  match _ = Nothing

app :: Pattern PrinterState JS (String, JS)
app = mkPattern' match
  where
  match (JSApp val args) = do
    jss <- mapM prettyPrintJS' args
    return (intercalate ", " jss, val)
  match _ = mzero

init' :: Pattern PrinterState JS (String, JS)
init' = mkPattern' match
  where
  match (JSInit val args) = do
    jss <- mapM prettyPrintJS' args
    return (intercalate ", " jss, val)
  match _ = mzero

typeOf :: Pattern PrinterState JS ((), JS)
typeOf = mkPattern match
  where
  match (JSTypeOf val) = Just ((), val)
  match _ = Nothing

instanceOf :: Pattern PrinterState JS (JS, JS)
instanceOf = mkPattern match
  where
  match (JSInstanceOf val ty) = Just (val, ty)
  match _ = Nothing

unary :: UnaryOperator -> String -> Operator PrinterState JS String
unary op str = Wrap match (++)
  where
  match :: Pattern PrinterState JS (String, JS)
  match = mkPattern match'
    where
    match' (JSUnary op' val) | op' == op = Just (str, val)
    match' _ = Nothing

binary :: BinaryOperator -> String -> Operator PrinterState JS String
binary op str = AssocL match (\v1 v2 -> v1 ++ " " ++ str ++ " " ++ v2)
  where
  match :: Pattern PrinterState JS (JS, JS)
  match = mkPattern match'
    where
    match' (JSBinary op' v1 v2) | op' == op = Just (v1, v2)
    match' _ = Nothing

prettyStatements :: [JS] -> StateT PrinterState Maybe String
prettyStatements sts = do
  jss <- forM sts prettyPrintJS'
  indentString <- currentIndent
  return $ intercalate "\n" $ map (indentString ++) jss

-- |
-- Generate a pretty-printed string representing a Javascript expression
--
prettyPrintJS1 :: JS -> String
prettyPrintJS1 = fromMaybe (error "Incomplete pattern") . flip evalStateT (PrinterState 0) . prettyPrintJS'

-- |
-- Generate a pretty-printed string representing a collection of Javascript expressions at the same indentation level
--
prettyPrintJS :: [JS] -> String
prettyPrintJS = fromMaybe (error "Incomplete pattern") . flip evalStateT (PrinterState 0) . prettyStatements

-- |
-- Generate an indented, pretty-printed string representing a Javascript expression
--
prettyPrintJS' :: JS -> StateT PrinterState Maybe String
prettyPrintJS' = A.runKleisli $ runPattern matchValue
  where
  matchValue :: Pattern PrinterState JS String
  matchValue = buildPrettyPrinter operators (literals <+> fmap parens matchValue)
  operators :: OperatorTable PrinterState JS String
  operators =
    OperatorTable [ [ Wrap accessor $ \prop val -> val ++ "." ++ prop ]
                  , [ Wrap indexer $ \index val -> val ++ "[" ++ index ++ "]" ]
                  , [ Wrap app $ \args val -> val ++ parens args ]
                  , [ Wrap init' $ \args val -> val ++ "{\n" ++ args ++ "}" ]
                  , [ unary JSNew "new " ]
                  , [ Wrap lam $ \(name, args) ret -> "func "
                        ++ fromMaybe "" name
                        ++ "(" ++ intercalate ", " args ++ ") "
                        ++ anyType
                        ++ " "
                        ++ ret ]
                  , [ Wrap dat' $ \name fields -> "\n"
                        ++ "type "
                        ++ name
                        ++ " struct "
                        ++ fields ]
                  , [ binary    LessThan             "<" ]
                  , [ binary    LessThanOrEqualTo    "<=" ]
                  , [ binary    GreaterThan          ">" ]
                  , [ binary    GreaterThanOrEqualTo ">=" ]
                  , [ Wrap typeOf $ \_ s -> "typeof " ++ s ]
                  , [ AssocR instanceOf $ \v1 v2 -> "reflect.TypeOf" ++ parens v1 ++ " == reflect.TypeOf" ++ parens ('C' : v2) ]

                  , [ unary     Not                  "!" ]
                  , [ unary     BitwiseNot           "~" ]
                  , [ unary     Negate               "-" ]
                  , [ unary     Positive             "+" ]
                  , [ binary    Multiply             "*" ]
                  , [ binary    Divide               "/" ]
                  , [ binary    Modulus              "%" ]
                  , [ binary    Add                  "+" ]
                  , [ binary    Subtract             "-" ]
                  , [ binary    ShiftLeft            "<<" ]
                  , [ binary    ShiftRight           ">>" ]
                  , [ binary    ZeroFillShiftRight   ">>>" ]
                  , [ binary    EqualTo              "==" ]
                  , [ binary    NotEqualTo           "!==" ]
                  , [ binary    BitwiseAnd           "&" ]
                  , [ binary    BitwiseXor           "^" ]
                  , [ binary    BitwiseOr            "|" ]
                  , [ binary    And                  "&&" ]
                  , [ binary    Or                   "||" ]
                  , [ Wrap conditional $ \(th, el) cond -> cond ++ " ? " ++ prettyPrintJS1 th ++ " : " ++ prettyPrintJS1 el ]
                    ]
