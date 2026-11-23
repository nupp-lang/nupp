/*
 * Codec-only XML benchmarks for smithy-java, written for the Nupp XML
 * baseline (bench/xml/smithy in the Nupp repository). run.sh copies this file
 * into smithy-java's benchmarks/serde-benchmarks/src/jmh/java tree, beside the
 * upstream RestXml and AwsQuery serde benchmarks whose fixtures it reuses.
 *
 * Decode feeds an XmlCodec exactly the bytes the client protocol would hand it
 * (the whole response body) and builds the output shape. Encode serializes the
 * input's body members, the same view of the input that
 * HttpBindingSerializer hands the codec. No HTTP header, label or query work
 * happens inside the measured loop, and no codec is built there either.
 *
 * Run as a program (main) it writes the cases' fixtures to a directory
 * instead: decode inputs, encode inputs (as the test case's params JSON) and
 * the bytes the codec produces for each encode case.
 */

package software.amazon.smithy.java.benchmarks.serde;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;
import org.openjdk.jmh.annotations.Benchmark;
import org.openjdk.jmh.annotations.Param;
import org.openjdk.jmh.annotations.Scope;
import org.openjdk.jmh.annotations.Setup;
import org.openjdk.jmh.annotations.State;
import org.openjdk.jmh.infra.Blackhole;
import software.amazon.smithy.java.aws.client.awsquery.AwsQueryClientProtocol;
import software.amazon.smithy.java.aws.client.restxml.RestXmlClientProtocol;
import software.amazon.smithy.java.client.http.HttpClientProtocol;
import software.amazon.smithy.java.codecs.commons.OutputBuffers;
import software.amazon.smithy.java.core.schema.ApiOperation;
import software.amazon.smithy.java.core.schema.Schema;
import software.amazon.smithy.java.core.schema.SerializableStruct;
import software.amazon.smithy.java.core.schema.TraitKey;
import software.amazon.smithy.java.core.serde.InterceptingSerializer;
import software.amazon.smithy.java.core.serde.ShapeSerializer;
import software.amazon.smithy.java.io.datastream.DataStream;
import software.amazon.smithy.java.io.datastream.PooledDataStream;
import software.amazon.smithy.java.xml.XmlCodec;
import software.amazon.smithy.model.node.Node;
import software.amazon.smithy.model.shapes.ShapeId;

public class CodecOnlyBenchmark {

    static final String RESTXML_PACKAGE = "software.amazon.smithy.java.benchmarks.serde.generated.restxml.model";
    static final ShapeId RESTXML_SERVICE = ShapeId.from("com.amazonaws.sdk.benchmark#AwsRestXmlDataPlane");
    static final String AWSQUERY_PACKAGE = "software.amazon.smithy.java.benchmarks.serde.generated.awsquery.model";
    static final ShapeId AWSQUERY_SERVICE = ShapeId.from("com.amazonaws.sdk.benchmark#AwsQueryDataPlane");
    static final String AWSQUERY_VERSION = "1999-12-31";
    static final String XML = "application/xml";
    static final byte[] EMPTY = new byte[0];

    /**
     * Suffix naming the one codec-only case with no upstream counterpart: CopyObjectRequest binds every member
     * to a header or label, so restXml sends no body and never calls the XML codec. This case serializes the
     * whole input through the codec instead, as XML elements, so encode has a flat many-string struct to measure.
     */
    static final String ALL_MEMBERS = "_AllMembersAsBody";

    static final List<String> DECODE_CASES = List.of(
            "awsQuery_GetMetricDataResponse_L",
            "awsQuery_GetMetricDataResponse_OutOfOrder",
            "restXml_WideTypesResponse_S",
            "restXml_WideTypesResponse_M",
            "restXml_WideTypesResponse_L",
            "restXml_CopyObjectOutput_M",
            "restXml_CopyObjectOutput_OutOfOrder");

    static final List<String> ENCODE_CASES = List.of(
            "restXml_WideTypesRequest_S",
            "restXml_WideTypesRequest_M",
            "restXml_WideTypesRequest_L",
            "restXml_CopyObjectRequest_M" + ALL_MEMBERS);

    @State(Scope.Benchmark)
    public static class Decode {
        @Param({
                "awsQuery_GetMetricDataResponse_L",
                "awsQuery_GetMetricDataResponse_OutOfOrder",
                "restXml_WideTypesResponse_S",
                "restXml_WideTypesResponse_M",
                "restXml_WideTypesResponse_L",
                "restXml_CopyObjectOutput_M",
                "restXml_CopyObjectOutput_OutOfOrder",
        })
        public String testCaseId;

        XmlCodec codec;
        ApiOperation<SerializableStruct, SerializableStruct> operation;
        byte[] body;

        @Setup
        public void setup() {
            prepare(testCaseId);
        }

        @SuppressWarnings({"unchecked", "rawtypes"})
        void prepare(String id) {
            boolean query = id.startsWith("awsQuery_");
            String pkg = query ? AWSQUERY_PACKAGE : RESTXML_PACKAGE;
            ShapeId service = query ? AWSQUERY_SERVICE : RESTXML_SERVICE;
            String contentType = query ? "text/xml" : XML;
            // The same state the upstream benchmark builds, so the bytes are the ones it feeds the protocol.
            var state = DeserializeState.forTestCase(id, pkg, service, EMPTY, contentType);
            operation = (ApiOperation) state.operation;
            body = bytes(state.response.body().asByteBuffer());
            String name = operation.schema().id().getName();
            if (query) {
                // AwsQueryClientProtocol#deserializeResponse builds this codec on every call; here it is built once.
                codec = XmlCodec.builder()
                        .wrapperElements(List.of(name + "Response", name + "Result"))
                        .strictRootElement(false)
                        .build();
            } else {
                // The codec RestXmlClientProtocol(serviceId) holds.
                codec = XmlCodec.builder()
                        .strictRootElement(false)
                        .outputBuffers(OutputBuffers.create())
                        .build();
            }

            // The codec must reach the same body members the protocol does.
            SerializableStruct viaProtocol;
            if (query) {
                viaProtocol = new AwsQueryClientProtocol(service, AWSQUERY_VERSION)
                        .deserializeResponse(operation, state.context, state.typeRegistry, state.request, state.response);
            } else {
                viaProtocol = new RestXmlClientProtocol(service)
                        .deserializeResponse(operation, state.context, state.typeRegistry, state.request, state.response);
            }
            SerializableStruct viaCodec = decode();
            byte[] expected = bodyBytes(viaProtocol);
            byte[] actual = bodyBytes(viaCodec);
            if (!Arrays.equals(expected, actual)) {
                throw new IllegalStateException("codec-only decode of " + id + " differs from the protocol's:\n"
                        + new String(expected, StandardCharsets.UTF_8) + "\n"
                        + new String(actual, StandardCharsets.UTF_8));
            }
        }

        SerializableStruct decode() {
            return codec.deserializeShape(ByteBuffer.wrap(body), operation.outputBuilder());
        }
    }

    @State(Scope.Benchmark)
    public static class Encode {
        @Param({
                "restXml_WideTypesRequest_S",
                "restXml_WideTypesRequest_M",
                "restXml_WideTypesRequest_L",
                "restXml_CopyObjectRequest_M" + ALL_MEMBERS,
        })
        public String testCaseId;

        XmlCodec codec;
        SerializableStruct input;

        @Setup
        public void setup() {
            prepare(testCaseId);
        }

        @SuppressWarnings({"unchecked", "rawtypes"})
        void prepare(String id) {
            boolean allMembers = id.endsWith(ALL_MEMBERS);
            String upstreamId = allMembers ? id.substring(0, id.length() - ALL_MEMBERS.length()) : id;
            var state = SerializeState.forTestCase(upstreamId, RESTXML_PACKAGE, RESTXML_SERVICE);
            // The codec RestXmlClientProtocol(serviceId) holds.
            codec = XmlCodec.builder()
                    .strictRootElement(false)
                    .outputBuffers(OutputBuffers.create())
                    .build();
            input = allMembers ? state.input : BodyMembers.of(state.input);
            if (allMembers) {
                return;
            }

            // The codec must write the body the protocol sends.
            var protocol = new RestXmlClientProtocol(RESTXML_SERVICE);
            ApiOperation<SerializableStruct, SerializableStruct> op = (ApiOperation) state.operation;
            var request = protocol.createRequest(op, state.input, state.context, state.endpoint);
            byte[] expected = bytes(request.body().asByteBuffer());
            SerializeState.releasePooledBody(protocol, request);
            byte[] actual = encodeToBytes();
            if (!Arrays.equals(expected, actual)) {
                throw new IllegalStateException("codec-only encode of " + id + " differs from the protocol's:\n"
                        + new String(expected, StandardCharsets.UTF_8) + "\n"
                        + new String(actual, StandardCharsets.UTF_8));
            }
        }

        byte[] encodeToBytes() {
            DataStream out = codec.serializeToDataStream(input, XML);
            byte[] result = bytes(out.asByteBuffer());
            release(out);
            return result;
        }
    }

    @Benchmark
    public void decode(Decode state, Blackhole bh) {
        bh.consume(state.decode());
    }

    /**
     * The leased path createRequest takes: serialize into a pooled buffer, then hand it back.
     */
    @Benchmark
    public void encode(Encode state, Blackhole bh) {
        DataStream out = state.codec.serializeToDataStream(state.input, XML);
        bh.consume(out);
        release(out);
    }

    static void release(DataStream out) {
        if (out instanceof PooledDataStream pooled) {
            pooled.release();
        }
    }

    static byte[] bytes(ByteBuffer buffer) {
        byte[] out = new byte[buffer.remaining()];
        buffer.duplicate().get(out);
        return out;
    }

    /** Serializes a shape's body members through a restXml codec, for comparing two decoded results. */
    static byte[] bodyBytes(SerializableStruct shape) {
        var codec = XmlCodec.builder().strictRootElement(false).build();
        return bytes(codec.serialize(BodyMembers.of(shape)));
    }

    /**
     * A struct showing only its members without an HTTP binding, as HttpBindingSerializer's StructBodyProxy
     * does (that class is package-private to http-binding).
     */
    record BodyMembers(SerializableStruct delegate, boolean[] body) implements SerializableStruct {
        static BodyMembers of(SerializableStruct struct) {
            List<Schema> members = struct.schema().members();
            boolean[] body = new boolean[members.size()];
            for (Schema member : members) {
                body[member.memberIndex()] = !(member.hasTrait(TraitKey.HTTP_HEADER_TRAIT)
                        || member.hasTrait(TraitKey.HTTP_LABEL_TRAIT)
                        || member.hasTrait(TraitKey.HTTP_QUERY_TRAIT)
                        || member.hasTrait(TraitKey.HTTP_QUERY_PARAMS_TRAIT)
                        || member.hasTrait(TraitKey.HTTP_PREFIX_HEADERS_TRAIT)
                        || member.hasTrait(TraitKey.HTTP_RESPONSE_CODE_TRAIT)
                        || member.hasTrait(TraitKey.HTTP_PAYLOAD_TRAIT));
            }
            return new BodyMembers(struct, body);
        }

        @Override
        public Schema schema() {
            return delegate.schema();
        }

        @Override
        public void serializeMembers(ShapeSerializer serializer) {
            delegate.serializeMembers(new InterceptingSerializer() {
                @Override
                protected ShapeSerializer before(Schema schema) {
                    return body[schema.memberIndex()] ? serializer : ShapeSerializer.nullSerializer();
                }
            });
        }

        @Override
        public <T> T getMemberValue(Schema member) {
            return delegate.getMemberValue(member);
        }
    }

    /**
     * Writes every case's fixtures to the directory named by the first argument: {@code <id>.xml} (decode
     * input), {@code <id>.params.json} (the test case's params: decode's expected result, encode's input) and
     * {@code <id>.expected.xml} (what the codec writes for an encode case). Each setup also checks the codec
     * against the protocol, so a run of this program is the like-for-like check.
     */
    public static void main(String[] args) throws IOException {
        Path out = Path.of(args[0]);
        Files.createDirectories(out);
        for (String id : DECODE_CASES) {
            var state = new Decode();
            state.prepare(id);
            Files.write(out.resolve(id + ".xml"), state.body);
            var params = BenchmarkTestCases.response(id).testCase().getParams();
            writeJson(out.resolve(id + ".params.json"), params);
        }
        for (String id : ENCODE_CASES) {
            var state = new Encode();
            state.prepare(id);
            Files.write(out.resolve(id + ".expected.xml"), state.encodeToBytes());
            String upstreamId = id.endsWith(ALL_MEMBERS) ? id.substring(0, id.length() - ALL_MEMBERS.length()) : id;
            var params = BenchmarkTestCases.request(upstreamId).testCase().getParams();
            writeJson(out.resolve(id + ".params.json"), params);
        }
    }

    private static void writeJson(Path path, Node node) throws IOException {
        Files.writeString(path, Node.prettyPrintJson(node == null ? Node.objectNode() : node) + "\n");
    }
}
