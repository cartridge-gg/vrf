pub mod Hashoor {
    pub fn hash1<T, +Drop<T>, +Serde<T>,>(a: T,) -> felt252 {
        let serialized = super::Calldata::serialize1(a);
        core::poseidon::poseidon_hash_span(serialized.span())
    }
    pub fn hash2<T, U, +Drop<T>, +Serde<T>, +Drop<U>, +Serde<U>>(a: T, b: U) -> felt252 {
        let serialized = super::Calldata::serialize2(a, b);
        core::poseidon::poseidon_hash_span(serialized.span())
    }
    pub fn hash3<T, U, V, +Drop<T>, +Serde<T>, +Drop<U>, +Serde<U>, +Drop<V>, +Serde<V>,>(
        a: T, b: U, c: V
    ) -> felt252 {
        let serialized = super::Calldata::serialize3(a, b, c);
        core::poseidon::poseidon_hash_span(serialized.span())
    }
    pub fn hash4<
        T,
        U,
        V,
        W,
        +Drop<T>,
        +Serde<T>,
        +Drop<U>,
        +Serde<U>,
        +Drop<V>,
        +Serde<V>,
        +Drop<W>,
        +Serde<W>,
    >(
        a: T, b: U, c: V, d: W
    ) -> felt252 {
        let serialized = super::Calldata::serialize4(a, b, c, d);
        core::poseidon::poseidon_hash_span(serialized.span())
    }
}

pub mod Calldata {
    pub fn serialize1<T, +Drop<T>, +Serde<T>>(a: T,) -> Array<felt252> {
        let mut arr = array![];
        a.serialize(ref arr);
        println!("serialize1: {:?}", arr);
        arr
    }
    pub fn serialize2<T, U, +Drop<T>, +Serde<T>, +Drop<U>, +Serde<U>,>(
        a: T, b: U
    ) -> Array<felt252> {
        let mut arr = array![];
        a.serialize(ref arr);
        b.serialize(ref arr);
        println!("serialize2: {:?}", arr);
        arr
    }
    pub fn serialize3<T, U, V, +Drop<T>, +Serde<T>, +Drop<U>, +Serde<U>, +Drop<V>, +Serde<V>,>(
        a: T, b: U, c: V
    ) -> Array<felt252> {
        let mut arr = array![];
        a.serialize(ref arr);
        b.serialize(ref arr);
        c.serialize(ref arr);
        println!("serialize3: {:?}", arr);
        arr
    }
    pub fn serialize4<
        T,
        U,
        V,
        W,
        +Drop<T>,
        +Serde<T>,
        +Drop<U>,
        +Serde<U>,
        +Drop<V>,
        +Serde<V>,
        +Drop<W>,
        +Serde<W>
    >(
        a: T, b: U, c: V, d: W
    ) -> Array<felt252> {
        let mut arr = array![];
        a.serialize(ref arr);
        b.serialize(ref arr);
        c.serialize(ref arr);
        d.serialize(ref arr);
        println!("serialize4: {:?}", arr);
        arr
    }
}