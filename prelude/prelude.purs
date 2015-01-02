module Prelude
  ( otherwise
  , flip
  , const
  , asTypeOf
  , Semigroupoid, (<<<), (>>>)
  , Category, id
  , ($), (#)
  , (:), cons
  , Show, show
  , Functor, (<$>), (<#>), void
  , Apply, (<*>)
  , Applicative, pure, liftA1
  , Bind, (>>=)
  , Monad, return, liftM1, ap
  , Num, (+), (-), (*), (/), (%)
  , negate
  , Eq, (==), (/=), refEq, refIneq
  , Ord, Ordering(..), compare, (<), (>), (<=), (>=)
  , Bits, (.&.), (.|.), (.^.), shl, shr, zshr, complement
  , BoolLike, (&&), (||)
  , not
  , Semigroup, (<>), (++)
  , Unit(..), unit
  ) where

  otherwise :: Boolean
  otherwise = true

  flip :: forall a b c. (a -> b -> c) -> b -> a -> c
  flip f b a = f a b

  const :: forall a b. a -> b -> a
  const a _ = a

  asTypeOf :: forall a. a -> a -> a
  asTypeOf x _ = x

  infixr 9 >>>
  infixr 9 <<<

  class Semigroupoid a where
    (<<<) :: forall b c d. a c d -> a b c -> a b d

  instance semigroupoidArr :: Semigroupoid (->) where
    (<<<) f g x = f (g x)

  (>>>) :: forall a b c d. (Semigroupoid a) => a b c -> a c d -> a b d
  (>>>) f g = g <<< f

  class (Semigroupoid a) <= Category a where
    id :: forall t. a t t

  instance categoryArr :: Category (->) where
    id x = x

  infixr 0 $
  infixl 0 #

  ($) :: forall a b. (a -> b) -> a -> b
  ($) f x = f x

  (#) :: forall a b. a -> (a -> b) -> b
  (#) x f = f x

  infixr 6 :

  (:) :: forall a. a -> [a] -> [a]
  (:) = cons

  foreign import cons
    "func Cons(e Any) Any {\
    \  return func(l Any) Any {\
    \    return append(l.([]Any), e);\
    \  };\
    \}" :: forall a. a -> [a] -> [a]

  class Show a where
    show :: a -> String

  foreign import showStringImpl """
    func ShowStringImpl(s Any) Any {
      return fmt.Sprintf("\"%s\"", s);
    }""" :: String -> String

  instance showUnit :: Show Unit where
    show (Unit {}) = "Unit {}"

  instance showString :: Show String where
    show = showStringImpl

  instance showBoolean :: Show Boolean where
    show true = "true"
    show false = "false"

  foreign import showNumberImpl "func ShowNumberImpl(n Any) Any {\
                                \  return fmt.Sprint(n);\
                                \}" :: Number -> String

  instance showNumber :: Show Number where
    show = showNumberImpl

  foreign import showArrayImpl """
  func ShowArrayImpl(f_ Any) Any {
    f := f_.(func (Any) Any)
    return func(xs_ Any) Any {
      xs := xs_.([]Any)
      last := len(xs) - 1
      var ss string
      for i, x := range xs {
        ss += f(x).(string)
        if last > 0 && i < last {
          ss += ","
        }
      }
      return "[" + ss + "]"
    }
  }""" :: forall a. (a -> String) -> [a] -> String

  instance showArray :: (Show a) => Show [a] where
    show = showArrayImpl show

  infixl 4 <$>
  infixl 1 <#>

  class Functor f where
    (<$>) :: forall a b. (a -> b) -> f a -> f b

  (<#>) :: forall f a b. (Functor f) => f a -> (a -> b) -> f b
  (<#>) fa f = f <$> fa

  void :: forall f a. (Functor f) => f a -> f Unit
  void fa = const unit <$> fa

  infixl 4 <*>

  class (Functor f) <= Apply f where
    (<*>) :: forall a b. f (a -> b) -> f a -> f b

  class (Apply f) <= Applicative f where
    pure :: forall a. a -> f a

  liftA1 :: forall f a b. (Applicative f) => (a -> b) -> f a -> f b
  liftA1 f a = pure f <*> a

  infixl 1 >>=

  class (Apply m) <= Bind m where
    (>>=) :: forall a b. m a -> (a -> m b) -> m b

  class (Applicative m, Bind m) <= Monad m

  return :: forall m a. (Monad m) => a -> m a
  return = pure

  liftM1 :: forall m a b. (Monad m) => (a -> b) -> m a -> m b
  liftM1 f a = do
    a' <- a
    return (f a')

  ap :: forall m a b. (Monad m) => m (a -> b) -> m a -> m b
  ap f a = do
    f' <- f
    a' <- a
    return (f' a')

  instance functorArr :: Functor ((->) r) where
    (<$>) = (<<<)

  instance applyArr :: Apply ((->) r) where
    (<*>) f g x = f x (g x)

  instance applicativeArr :: Applicative ((->) r) where
    pure = const

  instance bindArr :: Bind ((->) r) where
    (>>=) m f x = f (m x) x

  instance monadArr :: Monad ((->) r)

  infixl 7 *
  infixl 7 /
  infixl 7 %

  infixl 6 -
  infixl 6 +

  class Num a where
    (+) :: a -> a -> a
    (-) :: a -> a -> a
    (*) :: a -> a -> a
    (/) :: a -> a -> a
    (%) :: a -> a -> a
    negate :: a -> a

  foreign import numAdd "func NumAdd(n1 Any) Any {\
                        \  return func(n2 Any) Any {\
                        \    return n1.(int) + n2.(int);\
                        \  };\
                        \}" :: Number -> Number -> Number

  foreign import numSub "func NumSub(n1 Any) Any {\
                        \  return func(n2 Any) Any {\
                        \    return n1.(int) - n2.(int);\
                        \  };\
                        \}" :: Number -> Number -> Number

  foreign import numMul "func NumMul(n1 Any) Any {\
                        \  return func(n2 Any) Any {\
                        \    return n1.(int) * n2.(int);\
                        \  };\
                        \}" :: Number -> Number -> Number

  foreign import numDiv "func NumDiv(n1 Any) Any {\
                        \  return func(n2 Any) Any {\
                        \    return n1.(int) / n2.(int);\
                        \  };\
                        \}" :: Number -> Number -> Number

  foreign import numMod "func NumMod(n1 Any) Any {\
                        \  return func(n2 Any) Any {\
                        \    return n1.(int) % n2.(int);\
                        \  };\
                        \}" :: Number -> Number -> Number

  foreign import numNegate "func NumNegate(n Any) Any {\
                           \  return -(n.(int));\
                           \}" :: Number -> Number

  instance numNumber :: Num Number where
    (+) = numAdd
    (-) = numSub
    (*) = numMul
    (/) = numDiv
    (%) = numMod
    negate = numNegate

  newtype Unit = Unit {}

  unit :: Unit
  unit = Unit {}

  infix 4 ==
  infix 4 /=

  class Eq a where
    (==) :: a -> a -> Boolean
    (/=) :: a -> a -> Boolean

  foreign import refEq
    "func RefEq(r1 Any) Any {\
    \  return func(r2 Any) Any {\
    \    return r1 == r2;\
    \  };\
    \}" :: forall a. a -> a -> Boolean

  foreign import refIneq
    "func RefIneq(r1 Any) Any {\
    \  return func(r2 Any) Any {\
    \    return r1 != r2;\
    \  };\
    \}" :: forall a. a -> a -> Boolean

  instance eqUnit :: Eq Unit where
    (==) (Unit {}) (Unit {}) = true
    (/=) (Unit {}) (Unit {}) = false

  instance eqString :: Eq String where
    (==) = refEq
    (/=) = refIneq

  instance eqNumber :: Eq Number where
    (==) = refEq
    (/=) = refIneq

  instance eqBoolean :: Eq Boolean where
    (==) = refEq
    (/=) = refIneq

  foreign import eqArrayImpl"""
    func EqArrayImpl(f Any) Any {
      panic("eqArrayImpl not implemented")
    }""" :: forall a. (a -> a -> Boolean) -> [a] -> [a] -> Boolean

  instance eqArray :: (Eq a) => Eq [a] where
    (==) xs ys = eqArrayImpl (==) xs ys
    (/=) xs ys = not (xs == ys)

  data Ordering = LT | GT | EQ

  instance eqOrdering :: Eq Ordering where
    (==) LT LT = true
    (==) GT GT = true
    (==) EQ EQ = true
    (==) _  _  = false
    (/=) x y = not (x == y)

  instance showOrdering :: Show Ordering where
    show LT = "LT"
    show GT = "GT"
    show EQ = "EQ"

  class (Eq a) <= Ord a where
    compare :: a -> a -> Ordering

  infixl 4 <

  (<) :: forall a. (Ord a) => a -> a -> Boolean
  (<) a1 a2 = case a1 `compare` a2 of
    LT -> true
    _ -> false

  infixl 4 >

  (>) :: forall a. (Ord a) => a -> a -> Boolean
  (>) a1 a2 = case a1 `compare` a2 of
    GT -> true
    _ -> false

  infixl 4 <=

  (<=) :: forall a. (Ord a) => a -> a -> Boolean
  (<=) a1 a2 = case a1 `compare` a2 of
    GT -> false
    _ -> true

  infixl 4 >=

  (>=) :: forall a. (Ord a) => a -> a -> Boolean
  (>=) a1 a2 = case a1 `compare` a2 of
    LT -> false
    _ -> true

  foreign import unsafeCompareImpl """
    func UnsafeCompareImpl(lt Any)Any {
      return func(eq Any) Any {
        return func(gt Any) Any {
          return func(x Any) Any {
            return func(y Any) Any {
              if x.(int) < y.(int) {
                return lt
              } else if x.(int) > y.(int) {
                return gt
              } else {
                return eq
              }
            }
          }
        }
      }
    }""" :: forall a. Ordering -> Ordering -> Ordering -> a -> a -> Ordering

  unsafeCompare :: forall a. a -> a -> Ordering
  unsafeCompare = unsafeCompareImpl LT EQ GT

  instance ordUnit :: Ord Unit where
    compare (Unit {}) (Unit {}) = EQ

  instance ordBoolean :: Ord Boolean where
    compare false false = EQ
    compare false true  = LT
    compare true  true  = EQ
    compare true  false = GT

  instance ordNumber :: Ord Number where
    compare = unsafeCompare

  instance ordString :: Ord String where
    compare = unsafeCompare

  instance ordArray :: (Ord a) => Ord [a] where
    compare [] [] = EQ
    compare [] _ = LT
    compare _ [] = GT
    compare (x:xs) (y:ys) = case compare x y of
      EQ -> compare xs ys
      other -> other

  infixl 10 .&.
  infixl 10 .|.
  infixl 10 .^.

  class Bits b where
    (.&.) :: b -> b -> b
    (.|.) :: b -> b -> b
    (.^.) :: b -> b -> b
    shl :: b -> Number -> b
    shr :: b -> Number -> b
    zshr :: b -> Number -> b
    complement :: b -> b

  foreign import numShl "func NumShl(n1 Any) Any {\
                        \  return func(n2 Any) Any {\
                        \    return n1.(uint) << n2.(uint);\
                        \  };\
                        \}" :: Number -> Number -> Number

  foreign import numShr "func NumShr(n1 Any) Any {\
                        \  return func(n2 Any) Any {\
                        \    return n1.(uint) >> n2.(uint);\
                        \  };\
                        \}" :: Number -> Number -> Number

  foreign import numZshr "func NumZshr(n1 Any) Any {\
                          \  return func(n2 Any) Any {\
                          \    panic(\"n1 >>> n2\");\
                          \  };\
                          \}" :: Number -> Number -> Number

  foreign import numAnd "func NumAnd(n1 Any) Any {\
                        \  return func(n2 Any) Any {\
                        \    return n1.(uint) & n2.(uint);\
                        \  };\
                        \}" :: Number -> Number -> Number

  foreign import numOr "func NumOr(n1 Any) Any {\
                       \  return func(n2 Any) Any {\
                       \    return n1.(uint) | n2.(uint);\
                       \  };\
                       \}" :: Number -> Number -> Number

  foreign import numXor "func NumXor(n1 Any) Any {\
                        \  return func(n2 Any) Any {\
                        \    return n1.(uint) ^ n2.(uint);\
                        \  };\
                        \}" :: Number -> Number -> Number

  foreign import numComplement "func NumComplement(n Any) Any {\
                               \  return ^(n.(uint));\
                               \}" :: Number -> Number

  instance bitsNumber :: Bits Number where
    (.&.) = numAnd
    (.|.) = numOr
    (.^.) = numXor
    shl = numShl
    shr = numShr
    zshr = numZshr
    complement = numComplement

  infixr 2 ||
  infixr 3 &&

  class BoolLike b where
    (&&) :: b -> b -> b
    (||) :: b -> b -> b
    not :: b -> b

  foreign import boolAnd "func BoolAnd(b1 Any) Any {\
                         \  return func(b2 Any) Any {\
                         \    return b1.(bool) && b2.(bool);\
                         \  };\
                         \}"  :: Boolean -> Boolean -> Boolean

  foreign import boolOr "func BoolOr(b1 Any) Any {\
                        \  return func(b2 Any) Any {\
                        \    return b1.(bool) || b2.(bool);\
                        \  };\
                        \}" :: Boolean -> Boolean -> Boolean

  foreign import boolNot "func BoolNot(b Any) Any {\
                         \  return !(b.(bool));\
                         \}" :: Boolean -> Boolean

  instance boolLikeBoolean :: BoolLike Boolean where
    (&&) = boolAnd
    (||) = boolOr
    not = boolNot

  infixr 5 <>

  class Semigroup a where
    (<>) :: a -> a -> a

  foreign import concatString
    "func ConcatString(s1 Any) Any {\
    \  return func(s2 Any) Any {\
    \    return s1.(string) + s2.(string);\
    \  };\
    \}" :: String -> String -> String

  instance semigroupUnit :: Semigroup Unit where
    (<>) (Unit {}) (Unit {}) = Unit {}

  instance semigroupString :: Semigroup String where
    (<>) = concatString

  instance semigroupArr :: (Semigroup s') => Semigroup (s -> s') where
    (<>) f g = \x -> f x <> g x

  infixr 5 ++

  (++) :: forall s. (Semigroup s) => s -> s -> s
  (++) = (<>)

module Data.Function where

  on :: forall a b c. (b -> b -> c) -> (a -> b) -> a -> a -> c
  on f g x y = g x `f` g y

  foreign import data Fn0 :: * -> *
  foreign import data Fn1 :: * -> * -> *
  foreign import data Fn2 :: * -> * -> * -> *
  foreign import data Fn3 :: * -> * -> * -> * -> *
  foreign import data Fn4 :: * -> * -> * -> * -> * -> *
  foreign import data Fn5 :: * -> * -> * -> * -> * -> * -> *
  foreign import data Fn6 :: * -> * -> * -> * -> * -> * -> * -> *
  foreign import data Fn7 :: * -> * -> * -> * -> * -> * -> * -> * -> *
  foreign import data Fn8 :: * -> * -> * -> * -> * -> * -> * -> * -> * -> *
  foreign import data Fn9 :: * -> * -> * -> * -> * -> * -> * -> * -> * -> * -> *
  foreign import data Fn10 :: * -> * -> * -> * -> * -> * -> * -> * -> * -> * -> * -> *

  foreign import mkFn0
    "func MkFn0(fn Any) Any {\
    \  return func() Any {\
    \    return fn(nil);\
    \  };\
    \}" :: forall a. (Unit -> a) -> Fn0 a

  foreign import mkFn1
    "func MkFn1(fn Any) Any {\
    \  return func(a Any) Any {\
    \    return fn(a);\
    \  };\
    \}" :: forall a b. (a -> b) -> Fn1 a b

  foreign import mkFn2
    "func MkFn2(fn Any) Any {\
    \  return func(a, b Any) Any {\
    \    return fn(a)(b);\
    \  };\
    \}" :: forall a b c. (a -> b -> c) -> Fn2 a b c

  foreign import mkFn3
    "func MkFn3(fn Any) Any {\
    \  return func(a, b, c Any) Any {\
    \    return fn(a)(b)(c);\
    \  };\
    \}" :: forall a b c d. (a -> b -> c -> d) -> Fn3 a b c d

  foreign import mkFn4
    "func MkFn4(fn Any) Any {\
    \  return func(a, b, c, d Any) Any {\
    \    return fn(a)(b)(c)(d);\
    \  };\
    \}" :: forall a b c d e. (a -> b -> c -> d -> e) -> Fn4 a b c d e

  foreign import mkFn5
    "func MkFn5(fn Any) Any {\
    \  return func(a, b, c, d, e Any) Any {\
    \    return fn(a)(b)(c)(d)(e);\
    \  };\
    \}" :: forall a b c d e f. (a -> b -> c -> d -> e -> f) -> Fn5 a b c d e f

  foreign import mkFn6
    "func MkFn6(fn Any) Any {\
    \  return func(a, b, c, d, e, f Any) Any {\
    \    return fn(a)(b)(c)(d)(e)(f);\
    \  };\
    \}" :: forall a b c d e f g. (a -> b -> c -> d -> e -> f -> g) -> Fn6 a b c d e f g

  foreign import mkFn7
    "func MkFn7(fn Any) Any {\
    \  return func(a, b, c, d, e, f, g Any) Any {\
    \    return fn(a)(b)(c)(d)(e)(f)(g);\
    \  };\
    \}" :: forall a b c d e f g h. (a -> b -> c -> d -> e -> f -> g -> h) -> Fn7 a b c d e f g h

  foreign import mkFn8
    "func MkFn8(fn Any) Any {\
    \  return func(a, b, c, d, e, f, g, h Any) Any {\
    \    return fn(a)(b)(c)(d)(e)(f)(g)(h);\
    \  };\
    \}" :: forall a b c d e f g h i. (a -> b -> c -> d -> e -> f -> g -> h -> i) -> Fn8 a b c d e f g h i

  foreign import mkFn9
    "func MkFn9(fn Any) Any {\
    \  return func(a, b, c, d, e, f, g, h, i Any) Any {\
    \    return fn(a)(b)(c)(d)(e)(f)(g)(h)(i);\
    \  };\
    \}" :: forall a b c d e f g h i j. (a -> b -> c -> d -> e -> f -> g -> h -> i -> j) -> Fn9 a b c d e f g h i j

  foreign import mkFn10
    "func MkFn10(fn Any) Any {\
    \  return func(a, b, c, d, e, f, g, h, i, j Any) Any {\
    \    return fn(a)(b)(c)(d)(e)(f)(g)(h)(i)(j);\
    \  };\
    \}" :: forall a b c d e f g h i j k. (a -> b -> c -> d -> e -> f -> g -> h -> i -> j -> k) -> Fn10 a b c d e f g h i j k

  foreign import runFn0
    "func RunFn0(fn Any) Any {\
    \  return fn();\
    \}" :: forall a. Fn0 a -> a

  foreign import runFn1
    "func RunFn1(fn Any) Any {\
    \  return func(a Any) Any {\
    \    return fn(a);\
    \  };\
    \}" :: forall a b. Fn1 a b -> a -> b

  foreign import runFn2
    "func RunFn2(fn Any) Any {\
    \  return func(a Any) Any {\
    \    return func(b Any) Any {\
    \      return fn(a, b);\
    \    };\
    \  };\
    \}" :: forall a b c. Fn2 a b c -> a -> b -> c

  foreign import runFn3
    "func RunFn3(fn Any) Any {\
    \  return func(a Any) Any {\
    \    return func(b Any) Any {\
    \      return func(c Any) Any {\
    \        return fn(a, b, c);\
    \      };\
    \    };\
    \  };\
    \}" :: forall a b c d. Fn3 a b c d -> a -> b -> c -> d

  foreign import runFn4
    "func RunFn4(fn Any) Any {\
    \  return func(a Any) Any {\
    \    return func(b Any) Any {\
    \      return func(c Any) Any {\
    \        return func(d Any) Any {\
    \          return fn(a, b, c, d);\
    \        };\
    \      };\
    \    };\
    \  };\
    \}" :: forall a b c d e. Fn4 a b c d e -> a -> b -> c -> d -> e

  foreign import runFn5
    "func RunFn5(fn Any) Any {\
    \  return func(a Any) Any {\
    \    return func(b Any) Any {\
    \      return func(c Any) Any {\
    \        return func(d Any) Any {\
    \          return func(e Any) Any {\
    \            return fn(a, b, c, d, e);\
    \          };\
    \        };\
    \      };\
    \    };\
    \  };\
    \}" :: forall a b c d e f. Fn5 a b c d e f -> a -> b -> c -> d -> e -> f

  foreign import runFn6
    "func RunFn6(fn Any) Any {\
    \  return func(a Any) Any {\
    \    return func(b Any) Any {\
    \      return func(c Any) Any {\
    \        return func(d Any) Any {\
    \          return func(e Any) Any {\
    \            return func(f Any) Any {\
    \              return fn(a, b, c, d, e, f);\
    \            };\
    \          };\
    \        };\
    \      };\
    \    };\
    \  };\
    \}" :: forall a b c d e f g. Fn6 a b c d e f g -> a -> b -> c -> d -> e -> f -> g

  foreign import runFn7
    "func RunFn7(fn Any) Any {\
    \  return func(a Any) Any {\
    \    return func(b Any) Any {\
    \      return func(c Any) Any {\
    \        return func(d Any) Any {\
    \          return func(e Any) Any {\
    \            return func(f Any) Any {\
    \              return func(g Any) Any {\
    \                return fn(a, b, c, d, e, f, g);\
    \              };\
    \            };\
    \          };\
    \        };\
    \      };\
    \    };\
    \  };\
    \}" :: forall a b c d e f g h. Fn7 a b c d e f g h -> a -> b -> c -> d -> e -> f -> g -> h

  foreign import runFn8
    "func RunFn8(fn Any) Any {\
    \  return func(a Any) Any {\
    \    return func(b Any) Any {\
    \      return func(c Any) Any {\
    \        return func(d Any) Any {\
    \          return func(e Any) Any {\
    \            return func(f Any) Any {\
    \              return func(g Any) Any {\
    \                return func(h Any) Any {\
    \                  return fn(a, b, c, d, e, f, g, h);\
    \                };\
    \              };\
    \            };\
    \          };\
    \        };\
    \      };\
    \    };\
    \  };\
    \}" :: forall a b c d e f g h i. Fn8 a b c d e f g h i -> a -> b -> c -> d -> e -> f -> g -> h -> i

  foreign import runFn9
    "func RunFn9(fn Any) Any {\
    \  return func(a Any) Any {\
    \    return func(b Any) Any {\
    \      return func(c Any) Any {\
    \        return func(d Any) Any {\
    \          return func(e Any) Any {\
    \            return func(f Any) Any {\
    \              return func(g Any) Any {\
    \                return func(h Any) Any {\
    \                  return func(i Any) Any {\
    \                    return fn(a, b, c, d, e, f, g, h, i);\
    \                  };\
    \                };\
    \              };\
    \            };\
    \          };\
    \        };\
    \      };\
    \    };\
    \  };\
    \}" :: forall a b c d e f g h i j. Fn9 a b c d e f g h i j -> a -> b -> c -> d -> e -> f -> g -> h -> i -> j

  foreign import runFn10
    "func RunFn10(fn Any) Any {\
    \  return func(a Any) Any {\
    \    return func(b Any) Any {\
    \      return func(c Any) Any {\
    \        return func(d Any) Any {\
    \          return func(e Any) Any {\
    \            return func(f Any) Any {\
    \              return func(g Any) Any {\
    \                return func(h Any) Any {\
    \                  return func(i Any) Any {\
    \                    return func(j Any) Any {\
    \                      return fn(a, b, c, d, e, f, g, h, i, j);\
    \                    };\
    \                  };\
    \                };\
    \              };\
    \            };\
    \          };\
    \        };\
    \      };\
    \    };\
    \  };\
    \}" :: forall a b c d e f g h i j k. Fn10 a b c d e f g h i j k -> a -> b -> c -> d -> e -> f -> g -> h -> i -> j -> k

module Data.Eq where

  newtype Ref a = Ref a

  liftRef :: forall a b. (a -> a -> b) -> Ref a -> Ref a -> b
  liftRef f (Ref x) (Ref y) = f x y

  instance eqRef :: Eq (Ref a) where
    (==) = liftRef refEq
    (/=) = liftRef refIneq

  instance functorRef :: Functor Ref where
    (<$>) f (Ref x) = Ref (f x)

module Prelude.Unsafe where

  foreign import unsafeIndex """
    func UnsafeIndex(xs Any) Any {
      panic("unsafeIndex not implemented")
    }""" :: forall a. [a] -> Number -> a

module Control.Monad.Eff where

  foreign import data Eff :: # ! -> * -> *

  foreign import returnE "func ReturnE(a Any) Any {\
                         \    return a;\
                         \}" :: forall e a. a -> Eff e a

  foreign import bindE """
    func BindE(a_ Any) Any {
      a := a_.(func () Any)
      return func(f_ Any) Any {
        f := f_.(func (Any) Any)
        return func() Any {
          return f(a()).(func () Any)()
        }
      }
    }""" :: forall e a b. Eff e a -> (a -> Eff e b) -> Eff e b

  type Pure a = forall e. Eff e a

  foreign import runPure """
  func RunPure(f_ Any) Any {
    f := f_.(func () Any)
    return f()
  }""" :: forall a. Pure a -> a

  instance functorEff :: Functor (Eff e) where
    (<$>) = liftA1

  instance applyEff :: Apply (Eff e) where
    (<*>) = ap

  instance applicativeEff :: Applicative (Eff e) where
    pure = returnE

  instance bindEff :: Bind (Eff e) where
    (>>=) = bindE

  instance monadEff :: Monad (Eff e)

  foreign import untilE """
    func UntilE(f Any) Any {
      panic("untilE not implemented")
    }""" :: forall e. Eff e Boolean -> Eff e Unit

  foreign import whileE """
    func WhileE(f Any) Any {
      panic("whileE not implemented")
    }""" :: forall e a. Eff e Boolean -> Eff e a -> Eff e Unit

  foreign import forE """
    func ForE(lo Any) Any {
      panic("forE not implemented")
    }""" :: forall e. Number -> Number -> (Number -> Eff e Unit) -> Eff e Unit

  foreign import foreachE """
    func ForeachE(as Any) Any {
      panic("foreachE not implemented")
    }""" :: forall e a. [a] -> (a -> Eff e Unit) -> Eff e Unit

module Control.Monad.Eff.Unsafe where

  import Control.Monad.Eff

  foreign import unsafeInterleaveEff
    "func UnsafeInterleaveEff(f Any) Any {\
    \  return f;\
    \}" :: forall eff1 eff2 a. Eff eff1 a -> Eff eff2 a

module Debug.Trace where

  import Control.Monad.Eff

  foreign import data Trace :: !

  foreign import trace """
    func Trace(s Any) Any {
      fmt.Println(s)
      return func() Any {
        return nil
      }
    }""" :: forall r. String -> Eff (trace :: Trace | r) Unit

  print :: forall a r. (Show a) => a -> Eff (trace :: Trace | r) Unit
  print o = trace (show o)

  _ignoreUnused = runPure

module Control.Monad.ST where

  import Control.Monad.Eff

  foreign import data ST :: * -> !

  foreign import data STRef :: * -> * -> *

  foreign import newSTRef "func NewSTRef(val Any) Any {\
                          \  return func( Any) Any {\
                          \    return { value: val };\
                          \  };\
                          \}" :: forall a h r. a -> Eff (st :: ST h | r) (STRef h a)

  foreign import readSTRef "func ReadSTRef(ref Any) Any {\
                           \  return func( Any) Any {\
                           \    return ref.value;\
                           \  };\
                           \}" :: forall a h r. STRef h a -> Eff (st :: ST h | r) a

  foreign import modifySTRef "func ModifySTRef(ref Any) Any {\
                             \  return func(f Any) Any {\
                             \    return func( Any) Any {\
                             \      return ref.value = f(ref.value);\
                             \    };\
                             \  };\
                             \}" :: forall a h r. STRef h a -> (a -> a) -> Eff (st :: ST h | r) a

  foreign import writeSTRef "func WriteSTRef(ref Any) Any {\
                            \  return func(a Any) Any {\
                            \    return func( Any) Any {\
                            \      return ref.value = a;\
                            \    };\
                            \  };\
                            \}" :: forall a h r. STRef h a -> a -> Eff (st :: ST h | r) a

  foreign import runST "func RunST(f Any) Any {\
                       \  return f;\
                       \}" :: forall a r. (forall h. Eff (st :: ST h | r) a) -> Eff r a

  pureST :: forall a. (forall h r. Eff (st :: ST h | r) a) -> a
  pureST st = runPure (runST st)
