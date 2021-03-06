-----------------------------------------------------------------------------
--
-- Module      :  Language.PureScript.CodeGen.Cpp
-- Copyright   :  (c) _ 2013
-- License     :  MIT
--
-- Maintainer  :  _
-- Stability   :  experimental
-- Portability :
--
-- |
-- This module generates code in the simplified Javascript intermediate representation from Purescript code
--
-----------------------------------------------------------------------------
{-# LANGUAGE PatternGuards #-}

module Language.PureScript.CodeGen.Cpp where

import Data.List (elemIndices, intercalate, isPrefixOf, nub, nubBy, sortBy)
import Data.Char (isAlphaNum, isDigit, isSpace, toUpper)
import Data.Function (on)

import Control.Applicative

import Language.PureScript.CodeGen.JS.AST as AST
import Language.PureScript.CodeGen.JS.Common as Common
import Language.PureScript.CoreFn
import Language.PureScript.Names
import qualified Language.PureScript.Constants as C
import qualified Language.PureScript.Types as T

import Debug.Trace

preambleHeader :: ModuleName
preambleHeader = ModuleName [ProperName "Pure11"]

nativeMain :: [JS]
nativeMain =
  [ JSRaw "\n"
  , JSRaw "int main(int, char *[]) {"
  , JSRaw "    Main::main();"
  , JSRaw "    return 0;"
  , JSRaw "}"
  ]

-----------------------------------------------------------------------------------------------------------------------
data Type = Native String
          | Function Type Type
          | Data Type
          | Specialized Type [Type]
          | List Type
          | Template String
          | ParamTemplate String [Type]
          | EffectFunction Type
          deriving (Eq)

-----------------------------------------------------------------------------------------------------------------------
instance Show Type where
  show (Native name) = name
  show tt@(Function a b) = typeName tt ++ '<' : show a ++ "," ++ show b ++ ">"
  show tt@(EffectFunction b) = typeName tt ++ '<' : show b ++ ">"
  show tt@(Data t) = typeName tt ++ '<' : show t ++ ">"
  show (Specialized t []) = show t
  show (Specialized t ts) = show t ++ '<' : (intercalate "," $ map show ts) ++ ">"
  show tt@(List t) = typeName tt ++ '<' : show t ++ ">"
  show tt@(Template name) =  typeName tt ++ capitalize name
  show (Template []) = error "Bad template parameter"
  show (ParamTemplate name ts) = pname name ++ '<' : (intercalate "," $ map show ts) ++ ">"
    where
    pname s = '#' : show (length ts) ++ capitalize s

typeName :: Type -> String
typeName Function{} = "fn"
typeName EffectFunction{} = "eff_fn"
typeName Data{} = "data"
typeName List{} = "list"
typeName Template{} = "#"
typeName _ = ""

-----------------------------------------------------------------------------------------------------------------------
mktype :: ModuleName -> T.Type -> Maybe Type

mktype _ (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Number")))    = Just $ Native "double"
mktype _ (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "String")))    = Just $ Native "string"
mktype _ (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Boolean")))   = Just $ Native "bool"
mktype _ (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Integral"))) = Just $ Native "int"
mktype _ (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Int")))       = Just $ Native "int"
mktype _ (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Integer")))   = Just $ Native "long long"
mktype _ (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Char")))      = Just $ Native "char"

mktype _ (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prelude"])) (ProperName "Float")))  = Just $ Native "double"
mktype _ (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prelude"])) (ProperName "Double"))) = Just $ Native "double"

mktype _ (T.TypeApp
            (T.TypeApp
              (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Function")))
               T.REmpty) _) = error "Need to supprt func() T"

mktype m (T.TypeApp
            (T.TypeApp
              (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Function")))
               a) b) | Just a' <- mktype m a, Just b' <- mktype m b = Just $ Function a' b'
                     | otherwise = Nothing

mktype m (T.TypeApp
            (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Array")))
             a) | Just t <- mktype m a = Just $ List t
                | otherwise = Nothing

mktype _ (T.TypeApp
            (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Object")))
             T.REmpty) = Just $ Native "std::nullptr_t"

mktype m (T.TypeApp
            (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Object")))
             t@(T.RCons _ _ _)) = mktype m t

mktype m app@(T.TypeApp a b)
  | (name, tys@(_:_)) <- tyapp app [] = Just $ ParamTemplate (identToJs $ Ident name) tys
  where
    tyapp :: T.Type -> [Type] -> (String, [Type])
    tyapp (T.TypeApp (T.TypeVar name) b) ts | Just b' <- mktype m b = (identToJs $ Ident name, b':ts)
    tyapp (T.TypeApp (T.Skolem name _ _) b) ts | Just b' <- mktype m b = (identToJs $ Ident name, b':ts)
    tyapp (T.TypeApp inner@(T.TypeApp _ _) t) ts | Just t' <- mktype m t = tyapp inner (t':ts)
    tyapp _ _ = ([],[])

mktype m app@(T.TypeApp a b)
  | (name, tys@(_:_)) <- tyapp app [] = Just $ EffectFunction (last tys)
  where
    tyapp :: T.Type -> [Type] -> (String, [Type])
    -- tyapp (T.TypeApp (T.TypeVar name) b) ts | Just b' <- mktype m b = (identToJs $ Ident name, b':ts)
    tyapp (T.TypeApp (T.Skolem name _ _) b) ts | Just b' <- mktype m b = (identToJs $ Ident name, b':ts)
    tyapp (T.TypeApp (T.TypeConstructor name@(Qualified (Just _) (ProperName _))) b) ts
      | Just b' <- mktype m b = (qualifiedToStr m (Ident . runProperName) name, b':ts)
    tyapp (T.TypeApp inner@(T.TypeApp _ _) t) ts | Just t' <- mktype m t = tyapp inner (t':ts)
    tyapp _ _ = ([],[])

mktype m (T.TypeApp T.Skolem{} b) = mktype m b

mktype m app@(T.TypeApp a b)
  | (T.TypeConstructor _) <- a, [t] <- dataCon m app = Just $ Data t
  | (T.TypeConstructor _) <- a, (t:ts) <- dataCon m app = Just $ Data (Specialized t ts)
  | (T.TypeConstructor _) <- b, [t] <- dataCon m app = Just $ Data t
  | (T.TypeConstructor _) <- b, (t:ts) <- dataCon m app = Just $ Data (Specialized t ts)

mktype m (T.ForAll _ ty _) = mktype m ty
mktype _ (T.Skolem name _ _) = Just $ Template (identToJs $ Ident name)
mktype _ (T.TypeVar name) = Just $ Template (identToJs $ Ident name)
mktype _ (T.TUnknown n) = Just $ Template ('T' : show n)
mktype m a@(T.TypeConstructor _) = Just $ Data (Native $ qualDataTypeName m a)
mktype m (T.ConstrainedType _ ty) = mktype m ty
mktype m (T.RCons _ _ _) = Just $ Template "rowType"
mktype _ T.REmpty = Nothing
mktype _ b = error $ "Unknown type: " ++ show b

typestr :: ModuleName -> T.Type -> String
typestr m t | Just t' <- mktype m t = show t'
            | otherwise = []

-----------------------------------------------------------------------------------------------------------------------
fnArgStr :: ModuleName -> Maybe T.Type -> String
fnArgStr m (Just (T.TypeApp
                   (T.TypeApp
                     (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Function")))
                       a) _)) = typestr m a
fnArgStr m (Just (T.ForAll _ ty _)) = fnArgStr m (Just ty)
fnArgStr m (Just (T.TypeApp
                   (T.TypeApp
                     (T.TypeConstructor _) T.RCons{}) _)) = []  -- TODO:
fnArgStr m (Just (T.TypeApp
                   (T.TypeApp
                     (T.TypeConstructor _) a) _)) = typestr m a
fnArgStr _ _ = []
-----------------------------------------------------------------------------------------------------------------------
fnRetStr :: ModuleName -> Maybe T.Type -> String
fnRetStr m (Just (T.TypeApp
                   (T.TypeApp
                     (T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) (ProperName "Function")))
                       _) b)) = typestr m b
fnRetStr m (Just (T.ForAll _ ty _)) = fnRetStr m (Just ty)
fnRetStr m (Just (T.TypeApp
                   (T.TypeApp
                     (T.TypeConstructor _) _) b)) = typestr m b
fnRetStr _ _ = []
-----------------------------------------------------------------------------------------------------------------------
dataCon :: ModuleName -> T.Type -> [Type]
dataCon m (T.TypeApp a b) = (dataCon m a) ++ (dataCon m b)
dataCon m a@(T.TypeConstructor (Qualified (Just (ModuleName [ProperName "Prim"])) _))
  | Just a' <- mktype m a = [a']
  | otherwise = []
dataCon m a@(T.TypeConstructor _) = [Native $ qualDataTypeName m a]
dataCon m a
  | Just a' <- mktype m a = [a']
  | otherwise = []
-----------------------------------------------------------------------------------------------------------------------
qualDataTypeName :: ModuleName -> T.Type -> String
qualDataTypeName m (T.TypeConstructor typ) = intercalate "::" . words $ brk tname
  where
    tname = qualifiedToStr m (Ident . runProperName) typ
    brk = map (\c -> if c=='.' then ' ' else c)
qualDataTypeName _ _ = []
-----------------------------------------------------------------------------------------------------------------------
data Sort = Sort | NoSort deriving (Eq)
-----------------------------------------------------------------------------------------------------------------------
templDecl :: Sort -> String -> String
templDecl toSort s
  | ('#' `elem` s) = intercalate ", " (paramstr <$> templParms sort' s) ++ "|"
  where
    paramstr name@(c:_) | isDigit c = (subtype $ takeWhile isDigit name) ++ "class " ++ dropWhile isDigit name
    paramstr p = "typename " ++ dropWhile isDigit p
    subtype p = "template <" ++ intercalate "," ((++) "typename " <$> mkTs p) ++ "> "
    mkTs p = (('T' :) . show) <$> [1 .. read p]
    sort' = case toSort of
              Sort -> sortBy (compare `on` dropWhile isDigit)
              NoSort -> id
templDecl _ _ = []
-----------------------------------------------------------------------------------------------------------------------
templDecl' :: ModuleName -> Maybe T.Type -> String
templDecl' m (Just t)
  | s <- typestr m t = templDecl Sort s
templDecl' _ _ = ""
-----------------------------------------------------------------------------------------------------------------------
hasTemplates :: String -> Bool
hasTemplates s = '#' `elem` s
-----------------------------------------------------------------------------------------------------------------------
sections :: [JS] -> ([JS], [JS], [JS], [JS])
sections jss  = foldl (flip section) ([],[],[],[]) jss
  where
    section :: JS -> ([JS], [JS], [JS], [JS]) -> ([JS], [JS], [JS], [JS])

    section (JSNamespace name bs) (decls, impls, extTempls, templs) =
      let (ds, is, es, ts) = sections bs in
        (decls ++ take (length ds) [JSNamespace name ds],
         impls ++ take (length is) [JSNamespace name is],
         extTempls ++ take (length es) [JSNamespace name es],
         templs ++ take (length ts) [JSNamespace name ts])

    section (JSSequence name bs) (decls, impls, extTempls, templs) =
      let (ds, is, es, ts) = sections bs in
        (decls ++  take (length ds) [JSSequence name ds],
         impls ++ take (length is) [JSSequence name is],
         extTempls ++ take (length es) [JSSequence name es],
         templs ++ take (length ts) [JSSequence name ts])

    section (JSComment c js) (decls, impls, extTempls, templs) =
      let (ds, is, es, ts) = section js ([],[],[],[]) in
        (decls ++ ds,
         impls ++ is,
         extTempls ++ es,
         templs ++ ts)

    section (JSVariableIntroduction var (Just js@JSNamespace{})) (decls, impls, extTempls, templs) =
      section js (decls, impls, extTempls, templs)

    section (JSVariableIntroduction var (Just js@JSSequence{})) (decls, impls, extTempls, templs) =
      section js (decls, impls, extTempls, templs)

    -- | Typeclasses
    section js@(JSVariableIntroduction _ (Just (JSFunction (Just name) _ JSNoOp))) (decls, impls, extTempls, templs)
      | '|' `elem` name
      = (decls ++ [js],
         impls,
         extTempls,
         templs)

    section js@(JSVariableIntroduction var (Just (JSFunction (Just name) args _))) (decls, impls, extTempls, templs)
      | ('|':_) <- filter (not . isSpace) name
      = (decls,
         impls ++ [js],
         extTempls ++ [JSVariableIntroduction ("extern " ++ var) (Just $ JSFunction (Just name) args JSNoOp)],
         templs)

    section (JSVariableIntroduction var js@(Just (JSFunction (Just name) [arg] (JSBlock [JSReturn (JSApp _ [JSVar arg'])]))))
            (decls, impls, extTempls, templs)
      | ws@(_:_) <- words arg, last ws == arg'
      = (decls ++ [JSVariableIntroduction ("inline " ++ var) (Just $ JSFunction (Just name) [arg] JSNoOp)],
         impls,
         extTempls,
         templs ++ [JSVariableIntroduction ("inline " ++ var) js])

    section js@(JSVariableIntroduction var (Just (JSFunction (Just name) args _))) (decls, impls, extTempls, templs)
      | '|' `elem` name
      = (decls ++ [JSVariableIntroduction var (Just $ JSFunction (Just name) args JSNoOp)],
         impls,
         extTempls,
         templs ++ [js])

    section js@(JSVariableIntroduction var (Just (JSFunction (Just name) args _))) (decls, impls, extTempls, templs)
      = (decls ++ [JSVariableIntroduction var (Just $ JSFunction (Just name) args JSNoOp)],
         impls ++ [js],
         extTempls,
         templs)

    section js@(JSVariableIntroduction var (Just JSVar{})) (decls, impls, extTempls, templs)
      = (decls,
         impls,
         extTempls,
         templs ++ [js])

    section (JSVariableIntroduction var js@(Just JSNumericLiteral{})) (decls, impls, extTempls, templs)
      = (decls,
         impls,
         extTempls,
         templs ++ [JSVariableIntroduction ("const " ++ var) js])

    section (JSVariableIntroduction var js@(Just JSStringLiteral{})) (decls, impls, extTempls, templs)
      = (decls,
         impls,
         extTempls,
         templs ++ [JSVariableIntroduction ("const " ++ var) js])

    section (JSVariableIntroduction var js@(Just JSBooleanLiteral{})) (decls, impls, extTempls, templs)
      = (decls,
         impls,
         extTempls,
         templs ++ [JSVariableIntroduction ("const " ++ var) js])

    section (JSVariableIntroduction var js@(Just JSArrayLiteral{})) (decls, impls, extTempls, templs)
      = (decls,
         impls,
         extTempls,
         templs ++ [JSVariableIntroduction ("const " ++ var) js])

    section (JSVariableIntroduction var js@(Just JSApp{})) (decls, impls, extTempls, templs)
      = (decls,
         impls,
         extTempls,
         templs ++ [JSVariableIntroduction ("const " ++ var) js])

    section js@(JSVariableIntroduction var (Just JSData{})) (decls, impls, extTempls, templs)
      = (decls ++ [js],
         impls,
         extTempls,
         templs)

    -- TODO: check this case
    section (JSVariableIntroduction var (Just js)) (decls, impls, extTempls, templs) =
      let (ds, is, es, ts) = section js ([],[],[],[]) in
        (decls ++ ds,
         impls ++ is,
         extTempls ++ es,
         templs ++ ts)

    section _ (decls, impls, extTempls, templs) = (decls, impls, extTempls, templs)

-----------------------------------------------------------------------------------------------------------------------
dataTypes :: [Bind Ann] -> [JS]
dataTypes = map (JSVar . mkClass) . nub . filter (not . null) . map dataType
  where
    mkClass :: String -> String
    mkClass s = templateDecl ++ "struct " ++ rmType s ++ " { virtual ~" ++ rmType s ++ "(){} };"
      where
        templateDecl
          | t@('[':_:_:_) <- drop 1 $ getType s
            = "template " ++ '<' : intercalate ", " (tname <$> read t) ++ "> "
          | otherwise = []
        tname s = "typename " ++ capitalize s
-----------------------------------------------------------------------------------------------------------------------
dataType :: Bind Ann -> String
dataType (NonRec _ (Constructor (_, _, _, Just IsNewtype) _ _ _)) = []
dataType (NonRec _ (Constructor (_, _, _, _) name _ _)) = runProperName name
dataType _ = []
-----------------------------------------------------------------------------------------------------------------------
getAppSpecType :: ModuleName -> Expr Ann -> Int -> String
getAppSpecType m e l
    | (App (_, _, Just dty, _) _ _) <- e,
      (_:ts) <- dataCon m dty,
      ty@(_:_) <- drop l ts = '<' : intercalate "," (show <$> ty) ++ ">"
    | otherwise = []
-----------------------------------------------------------------------------------------------------------------------
qualifiedToStr :: ModuleName -> (a -> Ident) -> Qualified a -> String
qualifiedToStr _ f (Qualified (Just (ModuleName [ProperName mn])) a) | mn == C.prim = runIdent $ f a
qualifiedToStr m f (Qualified (Just m') a) | m /= m' = moduleNameToJs m' ++ "::" ++ identToJs (f a)
qualifiedToStr _ f (Qualified _ a) = identToJs (f a)
-----------------------------------------------------------------------------------------------------------------------
asDataTy :: String -> String
asDataTy t = "data<" ++ t ++ ">"
-----------------------------------------------------------------------------------------------------------------------
mkData :: String -> String
mkData t = "make_data<" ++ t ++ ">"
-----------------------------------------------------------------------------------------------------------------------
dataCtorName :: String
dataCtorName = "ctor"
-----------------------------------------------------------------------------------------------------------------------
mkDataFn :: String -> String
mkDataFn t = t ++ ':':':':dataCtorName
-----------------------------------------------------------------------------------------------------------------------
mkUnique :: String -> String
mkUnique s = '_' : s ++ "_"

mkUnique' :: Ident -> Ident
mkUnique' (Ident s) = Ident $ mkUnique s
mkUnique' ident = ident
-----------------------------------------------------------------------------------------------------------------------
addType :: String -> String
addType t = '@' : t
-----------------------------------------------------------------------------------------------------------------------
getType :: String -> String
getType = dropWhile (/='@')
-----------------------------------------------------------------------------------------------------------------------
getSpecialization :: String -> String
getSpecialization s = case spec of
                        ('<':ss) -> '<' : take (length ss - 2) ss ++ ">"
                        _ -> []
  where
    spec = dropWhile (/='<') . drop 1 $ dropWhile (/='<') s
-----------------------------------------------------------------------------------------------------------------------
rmTempl :: String -> String
rmTempl s | '|' `elem` s = drop 1 $ dropWhile (/='|') s
rmTempl s = s
-----------------------------------------------------------------------------------------------------------------------
rmType :: String -> String
rmType = takeWhile (/='@') . rmTempl
-----------------------------------------------------------------------------------------------------------------------
cleanName :: String -> String
cleanName s | ns@(_:_) <- elemIndices ':' s = takeWhile (/='<') $ drop (last ns + 1) (rmType s)
cleanName s | ws@(_:_) <- words (rmType s), head ws == "static" = last ws -- TODO: need better check
cleanName s = takeWhile (/='<') (last . words $ rmType s)
-----------------------------------------------------------------------------------------------------------------------
argType :: String -> String
argType s | ws@(_:_:_) <- (words $ rmType s) = intercalate " " $ init ws
-- argType s | (typ:_:_) <- words $ rmType s = typ
argType _ = []

argName :: String -> String
argName s | ws@(_:_) <- words $ rmType s = last ws
argName s = s
-----------------------------------------------------------------------------------------------------------------------
templParms :: ([String] -> [String]) -> String -> [String]
templParms f s = nub' . f $ (takeWhile (\c -> isAlphaNum c || c=='_') . flip drop s) <$> (map (+1) . elemIndices '#' $ s)
  where
    nub' :: [String] -> [String]
    nub' (s1@(h1:_):s2:ss)
      | (dropWhile isDigit s1) == (dropWhile isDigit s2) = nub' $ (if isDigit h1 then s1 else s2) : ss
    nub' (s:ss) = s : nub' ss
    nub' _ = []

-----------------------------------------------------------------------------------------------------------------------
templateSpec :: Maybe Type -> Maybe Type -> String
templateSpec (Just t1) (Just t2)
  | args@(_:_) <- intercalate "," $ snd <$> templateArgs t1 t2 = '<' : args ++ ">"
templateSpec _ _ = []

templateArgs :: Type -> Type -> [(String,String)]
templateArgs t1 t2 = nubBy ((==) `on` (normalize . fst)) . sortBy (compare `on` (normalize . fst)) $ templateArgs' [] t1 t2
  where
    normalize :: String -> String
    normalize = takeWhile (/='<') . dropWhile isDigit . filter (/='#')

templateArgs' :: [(String,String)] -> Type -> Type -> [(String,String)]
templateArgs' args (Native t) (Native t') | t == t' = args
templateArgs' args (Function a b) (Function a' b') = args ++ (templateArgs' [] a a') ++ (templateArgs' [] b b')
templateArgs' args (EffectFunction b) (EffectFunction b') = args ++ (templateArgs' [] b b')
templateArgs' args (Data t) (Data t') = templateArgs' args t t'
templateArgs' args (Specialized t []) (Specialized t' []) = templateArgs' args t t'
templateArgs' args (Specialized t ts) (Specialized t' ts') = args ++ (templateArgs' [] t t') ++ (concat $ zipWith (templateArgs' []) ts ts')
templateArgs' args (List t) (List t') = templateArgs' args t t'
templateArgs' args a@(Template "rowType") a'@(Template "rowType") = args ++ [(show a, [])]
templateArgs' args a@(Template _) a'@(Template _) = args ++ [(show a, show a')]
templateArgs' args a@(Template _) a' = args ++ [(show a, show a')]
templateArgs' args (ParamTemplate _ ts) (ParamTemplate _ ts') = args ++ zip (show <$> ts) (show <$> ts')
templateArgs' args a@(ParamTemplate _ _) a' = args ++ fromParamTemplate a a'
-- templateArgs' args Empty Empty = args
templateArgs' _ t1 t2 = error $ "Mismatched type structure! " ++ show t1 ++ " ; " ++ show t2

fromParamTemplate :: Type -> Type -> [(String,String)]
fromParamTemplate (ParamTemplate name ts) t
  | not (any isTemplate ts) = [(capitalize name, typeName t)]
  where
    isTemplate Template{} = True
    isTemplate _ = False
fromParamTemplate (ParamTemplate _ [a, b]) (Function a' b') =
  [ (show a, show a')
  , (show b, show b')
  ]
fromParamTemplate (ParamTemplate _ [b]) (EffectFunction b') =
  [ (show b, show b')
  ]
fromParamTemplate (ParamTemplate _ [a]) (List a') =
  [ (show a, show a')
  ]
fromParamTemplate (ParamTemplate _ [a]) (Data a') =
  [ (show a, show a')
  ]
fromParamTemplate (ParamTemplate _ [b]) (Function a' b') =
  [ (show a', show a') -- TODO: make sure this makes sense
  , (show b, show b')
  ]
fromParamTemplate ts t = error $ show "Can't map types! " ++ show ts ++ " ; " ++ show t
-----------------------------------------------------------------------------------------------------------------------
tyFromExpr :: Expr Ann -> T.Type
tyFromExpr (Abs (_, _, Just t, _) _ _) = t
tyFromExpr (App (_, _, Just t, _) _ _) = t
tyFromExpr (Var (_, _, Just t, _) _) = t
tyFromExpr (Literal (_, _, Just t, _) _) = t
tyFromExpr z = error $ show z -- T.REmpty
-----------------------------------------------------------------------------------------------------------------------
exprFnTy :: ModuleName -> Expr Ann -> Maybe Type
exprFnTy m (App (_, _, Just ty, _) val a)
  | Just nextTy <- exprFnTy m val = Just nextTy
  | Just a' <- argty m a,
    Just b' <- mktype m ty = Just $ Function a' b'
  | Just t' <- mktype m ty = Just t'
  where
    argty m (App (_, _, Just tt, _) _ _) = mktype m tt
    argty m (App (_, _, Nothing, _) val _) = argty m val
    argty m (Var (_, _, Just ty, _) _) = mktype m ty
    argty m (Literal (_, _, Just ty, _) _) = mktype m ty
    argty m (Var (_, _, Nothing, Nothing) _) = Nothing
    argty m (Accessor (_, _, Nothing, Nothing) _ _) = Nothing
    argty _ e = error $ "Unknown expression type! " ++ show e
exprFnTy m (App (_, _, Nothing, _) val _) = exprFnTy m val
exprFnTy _ _ = Nothing

-----------------------------------------------------------------------------------------------------------------------
declFnTy :: ModuleName -> Expr Ann -> Maybe Type
declFnTy m (Var (_, _, Just ty, _) _) = mktype m ty -- drop 3 . init $ typestr m ty -- strip outer "fn<>"
declFnTy m (App _ val _) = declFnTy m val
declFnTy _ _ = Nothing -- error $ "Can't find type: " ++ show m ++ ' ' : show t

-----------------------------------------------------------------------------------------------------------------------
typeclassTypes :: Expr Ann -> Qualified Ident -> [(String, T.Type)]
typeclassTypes (App (_, _, Just ty, _) _ _) (Qualified _ name) = zip (read (drop 1 . getType $ runIdent name)) (typeList ty [])
  where
    typeList :: T.Type -> [T.Type] -> [T.Type]
    typeList (T.TypeApp (T.TypeConstructor _) (T.RCons _ t _)) ts = typeList t ts
    typeList (T.TypeApp (T.TypeConstructor _) t) ts = typeList t ts
    typeList (T.TypeApp a b) ts = typeList a [] ++ typeList b ts
    typeList t ts = ts ++ [t]
typeclassTypes _ _ = []

convType :: [(String, T.Type)] -> T.Type -> T.Type
convType cts = flip (foldl (flip ($))) (T.everywhereOnTypes . skolemTo <$> cts)

convExpr :: (T.Type -> T.Type) -> Expr Ann -> Expr Ann
convExpr f (Abs (ss, com, Just ty, tt) arg val) = Abs (ss, com, Just (f ty), tt) arg (convExpr f val)
convExpr f (App (ss, com, Just ty, tt) val args) = App (ss, com, Just (f ty), tt) (convExpr f val) (convExpr f args)
convExpr f (Var (ss, com, Just ty, tt) ident) = Var (ss, com, Just (f ty), tt) ident
convExpr _ expr = expr

skolemTo :: (String, T.Type) -> T.Type -> T.Type
skolemTo (name', ty) (T.Skolem name _ _) | name == name' = ty
skolemTo _ ty = ty

typeclassTypeNames :: Expr Ann -> Qualified Ident -> [String]
typeclassTypeNames e ident = fst <$> typeclassTypes e ident

capitalize :: String -> String
capitalize (c:cs) = toUpper c : cs
capitalize s = s
-----------------------------------------------------------------------------------------------------------------------
isPrelude :: ModuleName -> Bool
isPrelude (ModuleName [ProperName "Prelude"]) = True
isPrelude _ = False

isMain :: ModuleName -> Bool
isMain (ModuleName [ProperName "Main"]) = True
isMain _ = False
-----------------------------------------------------------------------------------------------------------------------
depSort :: [(String, JS, a)] -> [(String, JS, a)]
depSort = sortBy vardep
  where
    getVars js = AST.everythingOnJS (++) getVar js

    getVar :: JS -> [String]
    getVar (JSVar name) = [takeWhile (/='<') $ rmType name]
    getVar _ = []

    vardep :: (String, JS, a) -> (String, JS, a) -> Ordering
    vardep (n1,j1,_) (n2,j2,_) | (identToJs $ Ident n1) `elem` (getVars j2) = LT
    vardep (n1,j1,_) (n2,j2,_) | (identToJs $ Ident n2) `elem` (getVars j1) = GT
    vardep _ _ = EQ

-----------------------------------------------------------------------------------------------------------------------
dropApp :: Expr Ann -> (Expr Ann, Int)
dropApp app = dropApp' app 0

dropApp' :: Expr Ann -> Int -> (Expr Ann, Int)
dropApp' (App _ val _) n = dropApp' val (n + 1)
dropApp' other n = (other, n)
-----------------------------------------------------------------------------------------------------------------------
valToAbs _ val@(Var vv@(ss, com, _, _) ident) = let argid = Ident "arg" in
  Abs vv argid (App vv val (Var (ss, com, Just T.REmpty, Nothing) (Qualified Nothing argid)))

valToAbs Nothing val@(App (_, _, Just (T.TypeConstructor _), _) _ Literal{}) = val

valToAbs (Just IsTypeClassConstructor) val@(App vv@(_, _, Just (T.TypeConstructor _), _) _ Literal{}) =
  Abs vv (Ident []) val

valToAbs _ val@(App vv@(ss, com, Just ty, _) _ _) = let argid = (Ident . fst $ abs' ty) in
  Abs (ss, com, Just . snd $ abs' ty, Nothing) argid (App vv val (Var (ss, com, Just T.REmpty, Nothing) (Qualified Nothing argid)))
  where
    -- TODO: this is probably too specific
    abs' (T.ForAll _ ty' _) = abs' ty'
    abs' (T.TypeApp (T.TypeApp (T.TypeConstructor _) (T.RCons _ (T.TypeConstructor _) (T.TUnknown _))) b) = ([], b)
    abs' ty'@T.TypeConstructor{} = ([], ty')
    abs' ty' = ("arg", ty')

valToAbs _ (Abs (ss, com, _, _) _ val@(App vv _ _)) = let argid = Ident "arg" in
  Abs vv argid (App vv val (Var (ss, com, Just T.REmpty, Nothing) (Qualified Nothing argid)))

valToAbs (Just IsTypeClassConstructor) val@(Literal vv _) =
  Abs vv (Ident []) val

valToAbs _ val = val
-----------------------------------------------------------------------------------------------------------------------
dataFields :: String -> [JS] -> [JS]
dataFields name jss = dataField <$> (zip jss [0..])
  where
    dataField (JSObjectLiteral fields, n)
      | (_:_) <- fields = JSObjectLiteral ((name ++ ' ' : show n, JSNoOp) : fields)
    dataField (js, _) = js
